#!/bin/bash

# Script to clean up Terraform files

# Remove .terraform directory
echo "Removing .terraform directory..."
rm -rf .terraform

# Remove .terraform.lock.hcl file
echo "Removing .terraform.lock.hcl file..."
rm -f .terraform.lock.hcl

# Remove all terraform.tfstate files
echo "Removing terraform.tfstate files..."
rm -f terraform.tfstate*
