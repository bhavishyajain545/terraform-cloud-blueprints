# Local equivalents of the CI jobs. No cloud credentials are needed for any target.
DIRS := modules/azure-network modules/azure-aks modules/aws-vpc modules/aws-eks envs/azure-dev envs/aws-dev

.PHONY: all fmt fmt-check validate test lint checkov docs docs-check clean

all: fmt-check validate test lint checkov docs-check

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive -diff

validate:
	@for d in $(DIRS); do \
	  echo "==> validate $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done

test:
	@for d in $(DIRS); do \
	  echo "==> test $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d test || exit 1; \
	done

lint:
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"

checkov:
	checkov --config-file .checkov.yaml

docs:
	@for d in $(DIRS); do terraform-docs --config .terraform-docs.yml $$d; done

docs-check:
	@for d in $(DIRS); do terraform-docs --config .terraform-docs.yml --output-check $$d || exit 1; done

clean:
	find . -type d -name .terraform -prune -exec rm -rf {} +
