import datetime
import json

import azure.functions as func

app = func.FunctionApp()


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
            - loan_amount (float): The requested loan amount in dollars
            - base_rate (float): The base interest rate as decimal
            - credit_score (int): Credit score (typically 300-850)
            - debt_to_income (float): Debt-to-income ratio as decimal

    Returns:
        func.HttpResponse: JSON response containing:
            - base_apr (float): Original base rate
            - adjusted_apr (float): Rate after credit and DTI adjustments
            - effective_apr (float): Final APR with markup, rounded to 2 decimals
            - credit_score (int): Input credit score
            - debt_to_income (float): Input DTI ratio
            - notes (str): Explanation of adjustments made

        Status codes: 200 (success), 500 (error)

    Raises:
        Returns HTTP 500 response for exceptions including:
        - Missing or invalid JSON parameters
        - Type conversion errors for numeric values

    Business Logic:
        - Credit adjustment: (700 - credit_score) × 0.0005
        - DTI adjustment: debt_to_income × 0.01
        - Loan amount tiers: <$5K (+0.75%), $5K-$25K (+0.25%),
          $25K-$75K (+0.5%), >$75K (+1.0%)
        - Final markup: +0.1% for effective APR
    """

    try:
        data = req.get_json()
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
            "notes": f"APR adjusted based on loan amount ({loan_amount}), credit score ({credit_score}) and DTI ({dti})",
        }

        return func.HttpResponse(
            json.dumps(response), mimetype="application/json", status_code=200
        )
    except Exception as e:
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="validation_tool")
@app.route(route="tools/validation_tool", methods=["POST"])
async def loan_validation(req: func.HttpRequest) -> func.HttpResponse:
    """
    Validate loan APR calculations by recalculating and comparing against provided values.

    This Azure Function performs server-side validation of APR calculations to ensure
    accuracy and consistency with business logic. It recalculates the expected APR
    using the same formula as the APR calculation tool and compares it with the
    provided calculated APR.

    Args:
        req (func.HttpRequest): HTTP request containing JSON payload with:
            - loan_amount (float): The requested loan amount in dollars
            - base_rate (float): The base interest rate
            - credit_score (int): Borrower's credit score (300-850 range)
            - debt_to_income (float): Debt-to-income ratio as decimal
            - calculated_apr (float): Previously calculated APR to validate

    Returns:
        func.HttpResponse: JSON response containing:
            - is_valid (bool): Whether calculated APR matches expected (±0.01 tolerance)
            - expected_apr (float): Server-calculated expected APR
            - calculated_apr (float): Original calculated APR from request
            - variance (float): Absolute difference between expected and calculated
            - loan_amount (float): Input loan amount
            - credit_score (int): Input credit score
            - debt_to_income (float): Input DTI ratio
            - validation_notes (str): Validation summary message

        Status codes: 200 (valid), 400 (invalid), 500 (error)

    Raises:
        ValueError: If required parameters are missing or invalid
        TypeError: If parameters cannot be converted to expected types

    Note:
        Uses identical calculation logic as apr_tool including credit score adjustments,
        DTI adjustments, loan amount tiers, and 0.1% effective APR markup.
    """

    try:
        data = req.get_json()

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
            "validation_notes": f"""
                APR validation {'passed' if is_valid else 'failed'}. 
                Expected: {expected_effective_apr}, 
                Calculated: {calculated_apr}
            """,
        }

        return func.HttpResponse(
            json.dumps(response),
            mimetype="application/json",
            status_code=200 if is_valid else 400,
        )
    except Exception as e:
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="compliance_tool")
@app.route(route="tools/compliance_tool", methods=["POST"])
async def compliance_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Validates loan compliance based on APR (Annual Percentage Rate) thresholds.
    This function performs simplified compliance checks for student loan processing
    by evaluating the effective APR against predefined regulatory thresholds.
    Args:
        req (func.HttpRequest): HTTP request containing JSON data with 'effective_apr' field.
            Expected JSON format: {"effective_apr": <float_value>}
    Returns:
        func.HttpResponse: JSON response containing compliance validation results.
            Success response format:
            {
                "compliance_passed": <bool>,
                "notes": <str>,
                "checked_on": <ISO_timestamp_string>
            Error response: HTTP 500 with error message string.
    Raises:
        Returns HTTP 500 response for any exceptions during processing, including:
        - Invalid JSON format
        - Missing 'effective_apr' field
        - Invalid APR value conversion
    Compliance Rules:
        - APR > 15.0%: Non-compliant (exceeds threshold)
        - APR < 2.0%: Non-compliant (likely miscalculated)
        - 2.0% <= APR <= 15.0%: Compliant
    Note:
        This implementation uses simplified rules for demonstration purposes.
        Production systems should implement comprehensive regulatory compliance checks.
    """

    try:
        data = req.get_json()
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
        return func.HttpResponse(json.dumps(result), mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(f"Error: {e}", status_code=500)


@app.function_name(name="amortization_tool")
@app.route(route="tools/amortization_tool", methods=["POST"])
async def amortization_tool(req: func.HttpRequest) -> func.HttpResponse:
    """
    Calculate loan amortization schedule and payment details.
    This function processes a loan amortization request by calculating the monthly payment,
    total interest, and a detailed payment schedule showing principal, interest, and
    remaining balance for each month of the loan term.
    Args:
        req (func.HttpRequest): HTTP request containing JSON data with:
            - loan_amount (float): The principal loan amount
            - effective_apr (float): Annual percentage rate as a percentage
            - term_years (int): Loan term in years
    Returns:
        func.HttpResponse: JSON response containing:
            - monthly_payment (float): Fixed monthly payment amount
            - total_interest (float): Total interest paid over loan term
            - schedule (list): List of dictionaries for each month containing:
                - month (int): Month number (1 to total months)
                - principal (float): Principal payment amount
                - interest (float): Interest payment amount
                - balance (float): Remaining loan balance
    Raises:
        Returns HTTP 500 status with error message if calculation fails or
        required parameters are missing/invalid.
    Example:
        Request body:
            "loan_amount": 200000.0,
            "effective_apr": 3.5,
            "term_years": 30
    """

    try:
        data = req.get_json()
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

        return func.HttpResponse(json.dumps(result), mimetype="application/json")

    except Exception as e:
        return func.HttpResponse(f"Error: {e}", status_code=500)
