import datetime
import json
import logging
from typing import Annotated

import azure.functions as func
from models import ApplicantFinancials, LoanApplication
from services import LoanApprovalService
from logging_config import configure_logging

configure_logging()
logger = logging.getLogger(__name__)
loan_approval_service = LoanApprovalService()
app = func.FunctionApp()


@app.function_name(name="loan_approval_metadata")
@app.route(route="mcp/loan_approval_metadata", methods=["GET"])
async def loan_approval_metadata(req: func.HttpRequest) -> func.HttpResponse:
    """
    Return metadata information about the Loan Approval MCP API.

    This Azure Function provides metadata about the Loan Approval API,
    including available tools, their descriptions, and input/output schemas.

    Args:
        req (func.HttpRequest): HTTP GET request.

    Returns:
        func.HttpResponse: JSON response containing metadata information
        about the Loan Approval MCP API.

    Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Errors in generating metadata.
    """

    logger.info("--- LOAN APPROVAL METADATA START ---")
    try:
        metadata = {
            "name": "Loan Approval MCP API",
            "version": "0.0.1-beta",
            "description": (
                "Provides tools for loan approval processing based on applicant "
                "financials."
            ),
            "auth": {
                "type": "connection",
                "connection_name": "function-app-api-key",
                "header": "x-functions-key",
                "description": (
                    "Uses the stored Azure AI Foundry connection "
                    "'function-app-api-key' to authenticate requests with the "
                    "x-functions-key header."
                ),
            },
            "tools": [
                {
                    "name": "calculateDTI",
                    "description": (
                        "Calculate debt-to-income ratio from financial information."
                    ),
                    "endpoint": "/api/tools/calculate_dti_tool",
                    "method": "POST",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "grossMonthlyIncome": {
                                "type": "number",
                                "description": ("Gross monthly income in dollars."),
                            },
                            "monthlyDebtPayments": {
                                "type": "number",
                                "description": (
                                    "Total monthly debt payments in dollars."
                                ),
                            },
                        },
                        "required": ["grossMonthlyIncome", "monthlyDebtPayments"],
                    },
                    "returns": {
                        "type": "object",
                        "properties": {
                            "dti": {
                                "type": "number",
                                "description": (
                                    "Calculated debt-to-income ratio percentage."
                                ),
                            },
                            "grossMonthlyIncome": {"type": "number"},
                            "monthlyDebtPayments": {"type": "number"},
                        },
                    },
                },
                {
                    "name": "evaluateLoanApplication",
                    "description": (
                        "Evaluate loan application and return approval decision "
                        "based on DTI."
                    ),
                    "endpoint": "/api/tools/evaluate_loan_application_tool",
                    "method": "POST",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "studentNumber": {"type": "string"},
                            "applicantName": {"type": "string"},
                            "loanAmount": {"type": "number"},
                            "grossMonthlyIncome": {"type": "number"},
                            "monthlyDebtPayments": {"type": "number"},
                            "dti": {
                                "type": "number",
                                "description": ("Optional pre-calculated DTI value."),
                                "nullable": True,
                            },
                        },
                        "required": [
                            "studentNumber",
                            "applicantName",
                            "loanAmount",
                            "grossMonthlyIncome",
                            "monthlyDebtPayments",
                        ],
                    },
                    "returns": {
                        "type": "object",
                        "properties": {
                            "decision": {
                                "type": "object",
                                "description": (
                                    "Loan approval decision including approval "
                                    "status and APR."
                                ),
                            }
                        },
                    },
                },
            ],
        }

        logger.info("--- LOAN APPROVAL METADATA SUCCESSFUL ---")
        return func.HttpResponse(
            json.dumps(metadata), mimetype="application/json", status_code=200
        )
    except Exception as e:
        logger.error("--- LOAN APPROVAL METADATA ERROR ---")
        logger.error(f"Error in loan approval metadata: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="apr_tool")
@app.route(route="tools/apr_tool", methods=["POST"])
async def apr_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Calculate loan APR based on financial parameters.

    This Azure Function calculates the Annual Percentage Rate (APR) for a loan
    by adjusting the base rate based on the applicant's credit score, debt-to-income
    ratio, and loan amount.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - loan_amount (float): The requested loan amount in dollars.
            - base_rate (float): The base interest rate as decimal.
            - credit_score (int): Credit score (typically 300-850).
            - debt_to_income (float): Debt-to-income ratio as decimal.

    Returns:
        func.HttpResponse: JSON response containing:
            - base_apr (float): Original base rate.
            - adjusted_apr (float): Rate after credit and DTI adjustments.
            - effective_apr (float): Final APR with markup, rounded to 2 decimals.
            - credit_score (int): Input credit score.
            - debt_to_income (float): Input DTI ratio.
            - notes (str): Explanation of adjustments made.

        Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Missing or invalid JSON parameters.
        - Type conversion errors for numeric values.

    Note:
        - Credit adjustment: (700 - credit_score) × 0.0005.
        - DTI adjustment: debt_to_income × 0.01.
        - Loan amount tiers: <$5K (+0.75%), $5K-$25K (+0.25%),
          $25K-$75K (+0.5%), >$75K (+1.0%).
        - Final markup: +0.1% for effective APR.
    """

    logger.info("--- APR TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"APR TOOL - Request data: {data}")
        loan_amount = float(data.get("loan_amount"))
        base_rate = float(data.get("base_rate"))
        credit_score = int(data.get("credit_score"))
        dti = float(data.get("debt_to_income"))

        # Simple interest rate adjustment based on credit score and DTI
        credit_adjustment = (700 - credit_score) * 0.0005
        dti_adjustment = dti * 0.01

        if loan_amount < 5000:
            loan_adjustment = 0.75
        elif loan_amount <= 25000:
            loan_adjustment = 0.25
        elif loan_amount <= 75000:
            loan_adjustment = 0.5
        else:
            loan_adjustment = 1.0

        apr = base_rate + credit_adjustment + dti_adjustment + loan_adjustment
        effective_apr = round(apr + 0.1, 2)

        response = {
            "base_apr": base_rate,
            "adjusted_apr": apr,
            "effective_apr": effective_apr,
            "credit_score": credit_score,
            "debt_to_income": dti,
            "notes": (
                f"APR adjusted based on loan amount ({loan_amount}), "
                f"credit score ({credit_score}) and DTI ({dti})"
            ),
        }

        logger.info("--- APR TOOL CALCULATION SUCCESSFUL ---")
        return func.HttpResponse(
            json.dumps(response), mimetype="application/json", status_code=200
        )
    except Exception as e:
        logger.error("--- APR TOOL ERROR ---")
        logger.error(f"Error in APR tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="validation_tool")
@app.route(route="tools/validation_tool", methods=["POST"])
async def loan_validation_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Validate loan APR calculations by recalculating and comparing against provided values.

    This Azure Function performs server-side validation of APR calculations to ensure
    accuracy and consistency with business logic. It recalculates the expected APR
    using the same formula as the APR calculation tool and compares it with the
    provided calculated APR.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - loan_amount (float): The requested loan amount in dollars.
            - base_rate (float): The base interest rate.
            - credit_score (int): Borrower's credit score (300-850 range).
            - debt_to_income (float): Debt-to-income ratio as decimal.
            - calculated_apr (float): Previously calculated APR to validate.

    Returns:
        func.HttpResponse: JSON response containing:
            - is_valid (bool): Whether calculated APR matches expected (±0.01 tolerance).
            - expected_apr (float): Server-calculated expected APR.
            - calculated_apr (float): Original calculated APR from request.
            - variance (float): Absolute difference between expected and calculated.
            - loan_amount (float): Input loan amount.
            - credit_score (int): Input credit score.
            - debt_to_income (float): Input DTI ratio.
            - validation_notes (str): Validation summary message.

        Status codes: 200 (valid), 400 (invalid), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Missing or invalid JSON parameters.
        - Type conversion errors for numeric values.

    Note:
        Uses identical calculation logic as apr_tool including credit score adjustments,
        DTI adjustments, loan amount tiers, and 0.1% effective APR markup.
    """
    logger.info("--- VALIDATION TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"VALIDATION TOOL - Request data: {data}")

        # Extract validation parameters
        loan_amount = float(data.get("loan_amount"))
        base_rate = float(data.get("base_rate"))
        credit_score = int(data.get("credit_score"))
        dti = float(data.get("debt_to_income"))
        calculated_apr = float(data.get("calculated_apr"))

        # Recalculate APR using same logic as apr_tool
        credit_adjustment = (700 - credit_score) * 0.0005
        dti_adjustment = dti * 0.01

        if loan_amount < 5000:
            loan_adjustment = 0.75
        elif loan_amount <= 25000:
            loan_adjustment = 0.25
        elif loan_amount <= 75000:
            loan_adjustment = 0.5
        else:
            loan_adjustment = 1.0

        expected_apr = base_rate + credit_adjustment + dti_adjustment + loan_adjustment
        expected_effective_apr = round(expected_apr + 0.1, 2)

        # Validate the calculated APR
        is_valid = abs(calculated_apr - expected_effective_apr) < 0.01

        response = {
            "is_valid": is_valid,
            "expected_apr": expected_effective_apr,
            "calculated_apr": calculated_apr,
            "variance": round(abs(calculated_apr - expected_effective_apr), 4),
            "loan_amount": loan_amount,
            "credit_score": credit_score,
            "debt_to_income": dti,
            "validation_notes": (
                f"APR validation {'passed' if is_valid else 'failed'}. "
                f"Expected: {expected_effective_apr}, "
                f"Calculated: {calculated_apr}"
            ),
        }

        logger.info("--- VALIDATION TOOL SUCCESSFUL ---")
        return func.HttpResponse(
            json.dumps(response),
            mimetype="application/json",
            status_code=200 if is_valid else 400,
        )
    except Exception as e:
        logger.error("--- VALIDATION TOOL ERROR ---")
        logger.error(f"Error in validation tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="compliance_tool")
@app.route(route="tools/compliance_tool", methods=["POST"])
async def compliance_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Validates loan compliance based on APR (Annual Percentage Rate) thresholds.

    This Azure Function performs simplified compliance checks for student loan processing
    by evaluating the effective APR against predefined regulatory thresholds.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - effective_apr (float): The effective APR value to validate.

    Returns:
        func.HttpResponse: JSON response containing:
            - compliance_passed (bool): Whether the APR complies with thresholds.
            - notes (str): Explanation of the compliance result.
            - checked_on (str): ISO timestamp of the compliance check.

        Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Invalid JSON format.
        - Missing 'effective_apr' field.
        - Invalid APR value conversion.

    Compliance Rules:
        - APR > 15.0%: Non-compliant (exceeds threshold).
        - APR < 2.0%: Non-compliant (likely miscalculated).
        - 2.0% <= APR <= 15.0%: Compliant.

    Note:
        This implementation uses simplified rules for demonstration purposes.
        Production systems should implement comprehensive regulatory compliance checks.
    """
    logger.info("--- COMPLIANCE TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"COMPLIANCE TOOL - Request data: {data}")
        apr = float(data.get("effective_apr"))

        # Simplified compliance rules for demo
        if apr > 15.0:
            compliant = False
            notes = "APR exceeds permissible threshold for student loan disclosures."
        elif apr < 2.0:
            compliant = False
            notes = "APR too low; likely miscalculated or subsidized incorrectly."
        else:
            compliant = True
            notes = "APR complies with federal and student loan disclosure regulations."

        result = {
            "compliance_passed": compliant,
            "notes": notes,
            "checked_on": datetime.datetime.utcnow().isoformat() + "Z",
        }
        logger.info("--- COMPLIANCE TOOL SUCCESSFUL ---")
        return func.HttpResponse(json.dumps(result), mimetype="application/json")
    except Exception as e:
        logger.error("--- COMPLIANCE TOOL ERROR ---")
        logger.error(f"Error in compliance tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="amortization_tool")
@app.route(route="tools/amortization_tool", methods=["POST"])
async def amortization_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Calculate loan amortization schedule and payment details.

    This Azure Function processes a loan amortization request by calculating the monthly payment,
    total interest, and a detailed payment schedule showing principal, interest, and
    remaining balance for each month of the loan term.

    Args:
        req (func.HttpRequest): HTTP request containing JSON data with:
            - loan_amount (float): The principal loan amount.
            - effective_apr (float): Annual percentage rate as a percentage.
            - term_years (int): Loan term in years.

    Returns:
        func.HttpResponse: JSON response containing:
            - monthly_payment (float): Fixed monthly payment amount.
            - total_interest (float): Total interest paid over loan term.
            - schedule (list): List of dictionaries for each month containing:
                - month (int): Month number (1 to total months).
                - principal (float): Principal payment amount.
                - interest (float): Interest payment amount.
                - balance (float): Remaining loan balance.

        Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 status with error message if calculation fails or
        required parameters are missing/invalid.

    Example:
        Request body:
            "loan_amount": 200000.0,
            "effective_apr": 3.5,
            "term_years": 30.
    """
    logger.info("--- AMORTIZATION TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"AMORTIZATION TOOL - Request data: {data}")
        loan_amount = float(data["loan_amount"])
        rate = float(data["effective_apr"])
        years = int(data["term_years"])

        r = rate / 100 / 12
        n = years * 12
        payment = loan_amount * r * (1 + r) ** n / ((1 + r) ** n - 1)
        balance = loan_amount
        schedule = []

        for month in range(1, n + 1):
            interest = balance * r
            principal = payment - interest
            balance -= principal
            schedule.append(
                {
                    "month": month,
                    "principal": round(principal, 2),
                    "interest": round(interest, 2),
                    "balance": round(max(balance, 0), 2),
                }
            )

        result = {
            "monthly_payment": round(payment, 2),
            "total_interest": round(payment * n - loan_amount, 2),
            "schedule": schedule,
        }

        logger.info("--- AMORTIZATION TOOL SUCCESSFUL ---")
        return func.HttpResponse(json.dumps(result), mimetype="application/json")
    except Exception as e:
        logger.error("--- AMORTIZATION TOOL ERROR ---")
        logger.error(f"Error in amortization tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="calculate_dti_tool")
@app.route(route="tools/calculate_dti_tool", methods=["POST"])
async def calculate_dti_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Calculate debt-to-income ratio (DTI) as a percentage.

    This Azure Function calculates the debt-to-income ratio (DTI) based on the
    gross monthly income and total monthly debt payments provided in the request.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - grossMonthlyIncome (float): Gross monthly income in dollars.
            - monthlyDebtPayments (float): Total monthly debt payments in dollars.

    Returns:
        func.HttpResponse: JSON response containing:
            - dti (float): Calculated debt-to-income ratio as a percentage.
            - grossMonthlyIncome (float): Input gross monthly income.
            - monthlyDebtPayments (float): Input total monthly debt payments.

        Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Missing or invalid JSON parameters.
        - Type conversion errors for numeric values.

    Formula:
        DTI = (monthly_debt_payments / gross_monthly_income) * 100.
    """
    logger.info("--- CALCULATE DTI TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"CALCULATE DTI TOOL - Request data: {data}")
        gross_monthly_income = float(data.get("grossMonthlyIncome"))
        monthly_debt_payments = float(data.get("monthlyDebtPayments"))

        logger.info(
            "calculateDTI called with grossMonthlyIncome=%s, monthlyDebtPayments=%s",
            gross_monthly_income,
            monthly_debt_payments,
        )

        financials = ApplicantFinancials(
            grossMonthlyIncome=gross_monthly_income,
            monthlyDebtPayments=monthly_debt_payments,
        )

        dti = loan_approval_service.calculate_dti(financials)

        response = {
            "dti": round(dti, 2),
            "grossMonthlyIncome": gross_monthly_income,
            "monthlyDebtPayments": monthly_debt_payments,
        }

        logger.info("--- CALCULATE DTI TOOL SUCCESSFUL ---")
        return func.HttpResponse(
            json.dumps(response), mimetype="application/json", status_code=200
        )
    except Exception as e:
        logger.error("--- CALCULATE DTI TOOL ERROR ---")
        logger.error(f"Error in calculate DTI tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="evaluate_loan_application_tool")
@app.route(route="tools/evaluate_loan_application_tool", methods=["POST"])
async def evaluate_loan_application_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Evaluate loan application using DTI-based business rules.

    This Azure Function evaluates a loan application based on the applicant's
    debt-to-income ratio (DTI) and other financial details. The decision is made
    according to predefined business rules.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - studentNumber (str): Unique identifier for the student.
            - applicantName (str): Full name of the applicant.
            - loanAmount (float): Requested loan amount in dollars.
            - grossMonthlyIncome (float): Gross monthly income in dollars.
            - monthlyDebtPayments (float): Total monthly debt payments in dollars.
            - dti (float, optional): Pre-calculated DTI (will calculate if not provided).

    Returns:
        func.HttpResponse: JSON response containing:
            - decision (dict): Decision details including approval status and APR.

        Status codes: 200 (success), 500 (error).

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Missing or invalid JSON parameters.
        - Type conversion errors for numeric values.

    Business Rules:
        - DTI > 45%: Reject.
        - 40% ≤ DTI ≤ 45%: Approve at 7.5% APR.
        - DTI < 40%: Approve at 5.5% APR.
    """
    logger.info("--- EVALUATE LOAN APPLICATION TOOL START ---")
    try:
        data = await req.get_json()
        logger.debug(f"EVALUATE LOAN APPLICATION TOOL - Request data: {data}")

        student_number = data.get("studentNumber")
        applicant_name = data.get("applicantName")
        loan_amount = float(data.get("loanAmount"))
        gross_monthly_income = float(data.get("grossMonthlyIncome"))
        monthly_debt_payments = float(data.get("monthlyDebtPayments"))
        dti = data.get("dti")

        if dti is not None:
            dti = float(dti)

        logger.info(
            "evaluateLoanApplication called for applicant=%s (Student#: %s), amount=$%.2f",
            applicant_name,
            student_number,
            loan_amount,
        )

        financials = ApplicantFinancials(
            grossMonthlyIncome=gross_monthly_income,
            monthlyDebtPayments=monthly_debt_payments,
            dti=dti,
        )

        application = LoanApplication(
            studentNumber=student_number,
            applicantName=applicant_name,
            loanAmount=loan_amount,
            financials=financials,
        )

        decision = loan_approval_service.evaluate_loan_application(application)

        logger.info("--- EVALUATE LOAN APPLICATION TOOL SUCCESSFUL ---")
        return func.HttpResponse(
            json.dumps(decision.model_dump()),
            mimetype="application/json",
            status_code=200,
        )
    except Exception as e:
        logger.error("--- EVALUATE LOAN APPLICATION TOOL ERROR ---")
        logger.error(f"Error in evaluate loan application tool: {e}")
        return func.HttpResponse(f"Error: {e}", status_code=500)
