import json
import os
import sys

# This script analyzes the Terraform plan output in JSON format to detect potential issues such as resource deletions, security risks, and large changes. 
# It is designed to be used in a CI/CD pipeline to automatically evaluate the impact of proposed infrastructure changes before they are applied.

def analyze_plan(file_path):
    print(f"Analyzing Terraform plan file: {file_path}")

    with open(file_path, "r") as f:
        plan = json.load(f)

    print("Plan loaded successfully. Analyzing resource changes...")

    resource_changes = plan.get("resource_changes", [])

    delete_detected = False
    security_risk = False
    large_changes = False

    for resource in resource_changes:
        actions = resource.get("change", {}).get("actions", [])
        resource_type = resource.get("type", "")
        name = resource.get("name", "")

        if "delete" in actions:
            delete_detected = True
            print(f"Resource marked for deletion: {resource_type}.{name}")
        
        if actions == ["delete", "create"]:
            large_changes = True
            print(f"Resource will be replaced: {resource_type}.{name}")
        
        after = resource.get("change", {}).get("after", {})

        # Check for security group rules that allow SSH from anywhere
        if resource_type == "aws_security_group":
            ingress = after.get("ingress", [])
            for rule in ingress:
                if "0.0.0.0/0" in rule.get("cidr_blocks", []) and rule.get("from_port") == 22 and rule.get("to_port") == 22:
                    security_risk = True
                    print(f"Security risk detected: {resource_type}.{name} allows SSH from anywhere")

        # check for s3 public access
        if resource_type == "aws_s3_bucket":
            acl = after.get("acl", "")
            if acl in ["public-read", "public-read-write"]:
                security_risk = True
                print(f"Security risk detected: {resource_type}.{name} has public ACL")
                

    # final analysis
    if delete_detected or security_risk or large_changes:
        print("\nPlan analysis detected potential issues:")
        if delete_detected:
            print("- Resource deletions detected")
        if security_risk:
            print("- Security risks detected")
        if large_changes:
            print("- Large changes detected")
        sys.exit(1)
    else:
        print("\nPlan analysis did not detect any issues")
        sys.exit(0)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyze_plan.py <plan.json>")
        sys.exit(1)

    plan_file = sys.argv[1]
    analyze_plan(plan_file)