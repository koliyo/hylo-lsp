#!/bin/bash

start_heading="## $1"

end_heading="#"

# The file to process
file="CHANGELOG.md"

awk -v start="$start_heading" -v end="$end_heading" '
    $0 ~ start {flag=1; next}
    $0 ~ end {flag=0}
    flag {print}
' "$file"
