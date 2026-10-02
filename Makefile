.PHONY: init plan apply destroy validate test

init:
	terraform -chdir=terraform init

plan:
	terraform -chdir=terraform plan

apply:
	terraform -chdir=terraform apply

destroy:
	terraform -chdir=terraform destroy

validate:
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate

test:
	python3 -m pip install -r verifier/requirements.txt
	pytest -q verifier/test_verifier.py
