
# ------------------------------------
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
# ------------------------------------

import json
import datetime
from typing import Any, Callable, Set, Dict, List, Optional
TEN_K= 10000

# These are the user-defined functions that can be called by the agent.


def calculate_new_loan(a: int) -> str:
    """Calculates the new loan amount.

    :param a (int): loan amount.
    :rtype: int

    :return: add $10,000 to the loan amount.
    :rtype: str
    """
    result = a + TEN_K
    return json.dumps({"result": result})



# Example User Input for Each Function
# 1. Add $10,000 top the loan ammount 
#    User Input: "Add 10K to loan <loan_number>."
#    User Input: "Add 10000 to loan <loan_number>."
#    User Input: "Add $10,000 to loan <loan_number>."


# Statically defined user functions for fast reference
functions: Set[Callable[..., Any]] = {
    calculate_new_loan,
}