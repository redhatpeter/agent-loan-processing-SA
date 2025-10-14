"""
Test configuration and fixtures for pytest.
"""

import pytest
import os
import sys
from pathlib import Path

# Add src directory to Python path
project_root = Path(__file__).parent.parent
src_path = project_root / "src"
sys.path.insert(0, str(src_path))

@pytest.fixture
def sample_data_dir():
    """Fixture to provide path to sample data directory."""
    return project_root / "data"

@pytest.fixture
def temp_output_dir(tmp_path):
    """Fixture to provide temporary output directory for tests."""
    return tmp_path / "output"

@pytest.fixture
def sample_pdf_path(sample_data_dir):
    """Fixture to provide path to sample PDF file."""
    return sample_data_dir / "StudentLoans" / "test-fillable-form.pdf"