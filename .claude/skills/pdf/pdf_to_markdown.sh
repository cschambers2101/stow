#!/bin/bash

# PDF to Markdown Converter
# Extracts text from PDF files and saves to markdown format
# Requires: pdftotext (from poppler-utils)

set -euo pipefail

usage() {
    echo "Usage: $0 <pdf_file_or_directory> [output.md]"
    echo ""
    echo "Arguments:"
    echo "  pdf_file_or_directory  A single PDF file or directory containing PDFs"
    echo "  output.md              Output markdown file (default: output.md)"
    echo ""
    echo "Examples:"
    echo "  $0 document.pdf"
    echo "  $0 document.pdf result.md"
    echo "  $0 ./pdfs/ combined.md"
    exit 1
}

check_dependencies() {
    if ! command -v pdftotext &> /dev/null; then
        echo "Error: pdftotext is not installed."
        echo ""
        echo "Install it with:"
        echo "  macOS:  brew install poppler"
        echo "  Ubuntu: sudo apt-get install poppler-utils"
        echo "  Fedora: sudo dnf install poppler-utils"
        exit 1
    fi
}

process_pdf() {
    local pdf_file="$1"
    local output_file="$2"
    local filename
    filename=$(basename "$pdf_file")

    echo "Processing: $filename"

    # Add header for this PDF
    {
        echo ""
        echo "---"
        echo ""
        echo "# $filename"
        echo ""
        echo "_Extracted from: ${pdf_file}_"
        echo ""
    } >> "$output_file"

    # Extract text and append to output
    # -layout preserves the original layout
    # -enc UTF-8 ensures proper encoding
    if pdftotext -layout -enc UTF-8 "$pdf_file" - >> "$output_file" 2>/dev/null; then
        echo "  ✓ Successfully extracted text"
    else
        echo "  ✗ Failed to extract text from $filename" >&2
        echo "_Error: Could not extract text from this PDF_" >> "$output_file"
    fi

    echo "" >> "$output_file"
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    check_dependencies

    local input="$1"
    local output="${2:-output.md}"
    local pdf_count=0

    # Initialize output file with header
    {
        echo "# PDF Text Extraction"
        echo ""
        echo "_Generated on: $(date)_"
        echo ""
    } > "$output"

    if [[ -f "$input" ]]; then
        # Single file mode
        if [[ "$input" == *.pdf || "$input" == *.PDF ]]; then
            process_pdf "$input" "$output"
            pdf_count=1
        else
            echo "Error: File must be a PDF"
            exit 1
        fi
    elif [[ -d "$input" ]]; then
        # Directory mode - process all PDFs
        while IFS= read -r -d '' pdf_file; do
            process_pdf "$pdf_file" "$output"
            ((pdf_count++))
        done < <(find "$input" -maxdepth 1 -type f \( -name "*.pdf" -o -name "*.PDF" \) -print0 | sort -z)

        if [[ $pdf_count -eq 0 ]]; then
            echo "No PDF files found in $input"
            exit 1
        fi
    else
        echo "Error: '$input' is not a valid file or directory"
        exit 1
    fi

    echo ""
    echo "Done! Processed $pdf_count PDF(s)"
    echo "Output saved to: $output"
}

main "$@"
