# Agentic AI Form Processing

An AI-powered form processing system that uses agentic workflows to intelligently process and fill PDF forms.

## Description

This project implements an intelligent form processing system using AI agents to:
- Process PDF forms automatically
- Extract and understand form fields
- Fill forms with appropriate data
- Handle complex form validation and processing

## Features

- PDF form processing and filling
- AI-powered data extraction
- Automated form validation
- Support for multiple form types
- Data processing pipeline

## Project Structure

```
├── .gitignore                   # Git ignore file
├── LICENSE                      # MIT License
├── README.md                    # Project documentation
├── setup.py                     # Python package setup
├── requirements.txt             # Python dependencies
├── environment.env.example      # Environment configuration template
├── src/                         # Source code package
│   ├── __init__.py             # Package initialization
│   ├── agents/                 # AI agent implementations
│   │   └── __init__.py
│   ├── core/                   # Core processing modules
│   │   └── __init__.py
│   ├── utils/                  # Utility functions
│   │   └── __init__.py
│   └── oldcodes-ipynb/         # Original Jupyter notebooks
├── tests/                      # Test suite
│   ├── __init__.py
│   └── conftest.py             # pytest configuration
├── data/                       # Sample data files
│   ├── Promissory_Note_Dummy_Data__50_rows_ (1).csv
│   └── Promissory_Note_Dummy_Data__50_rows_.json
├── StudentLoans/               # Student loan specific forms
│   ├── combined_dummy_data_cleaned.xlsx
│   ├── student_loan_disbursement_packet_fillable_multipage.pdf
│   └── test-fillable-form.pdf
├── docs/                       # Documentation
├── input/                      # Input files directory
├── output/                     # Output files directory
├── logs/                       # Application logs
└── backup/                     # Backup files
```

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd AgenticAIFormProcessing
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Set up environment variables:
```bash
cp environment.env.example environment.env
# Edit environment.env with your configuration
```

## Usage

### Development Setup
1. Install the package in development mode:
```bash
pip install -e .
```

2. For development with additional tools:
```bash
pip install -e ".[dev]"
```

### Using the Package
1. Import and use the core functionality:
```python
from src.core import FormProcessor, PDFHandler, DataExtractor
from src.agents import PDFAgent, FormFillerAgent
from src.utils import Config, setup_logger

# Initialize components
config = Config()
logger = setup_logger()
processor = FormProcessor(config)

# Process forms
result = processor.process_form(input_path, output_path)
```

2. Explore original research notebooks (located in `src/oldcodes-ipynb/`):
   - Original agent implementations
   - PDF form filling examples  
   - Search functionality experiments

### Running Tests
```bash
# Run all tests
pytest

# Run tests with coverage
pytest --cov=src

# Run specific test file
pytest tests/test_specific.py
```

## Configuration

Create your environment configuration files:
- `environment.env` - Main environment variables
- `globalparameters.env` - Global parameters

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

For questions or support, please open an issue in the repository.