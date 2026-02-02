---
name: pdf
description: Use this skill when you need to read or process PDF files. Converts PDFs to markdown for reliable text extraction, especially for large PDFs that exceed size limits.
allowed-tools:
  - Bash
  - Read
  - Glob
---

# PDF Reading Skill

When you need to read content from a PDF file, use this skill to convert it to markdown first, then read the markdown file.

## Why Use This Skill

- Large PDFs often fail to load due to size limits
- PDF text extraction is more reliable through pdftotext
- Markdown output preserves layout and is easier to process
- Works with single files or entire directories of PDFs

## How to Process PDFs

### Step 1: Convert PDF to Markdown

Use the pdf_to_markdown.sh script located in this skill's directory:

```bash
# Single PDF file
pdf_to_markdown.sh "/path/to/file.pdf" "/tmp/pdf_output.md"

# Multiple PDFs in a directory
pdf_to_markdown.sh "/path/to/pdf_directory/" "/tmp/combined_output.md"
```

### Step 2: Read the Markdown Output

After conversion, read the markdown file using the Read tool:

```
Read /tmp/pdf_output.md
```

### Step 3: Clean Up (Optional)

Remove temporary markdown files when done:

```bash
rm /tmp/pdf_output.md
```

## Workflow Example

When a user asks you to read or analyze a PDF:

1. First, convert the PDF to markdown using the script
2. Read the generated markdown file
3. Process/analyze the content as requested
4. Provide your response based on the extracted text

## Requirements

The script requires `pdftotext` from poppler. If not installed:
- macOS: `brew install poppler`
- Ubuntu: `sudo apt-get install poppler-utils`

## Notes

- The script preserves text layout from the original PDF
- UTF-8 encoding is used for proper character support
- Failed extractions are noted in the output file
- For very large PDFs, you may need to read the markdown file in chunks using offset/limit parameters
