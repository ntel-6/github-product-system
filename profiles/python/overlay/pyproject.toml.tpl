[project]
name = "{{PRODUCT_NAME}}"
version = "0.1.0"
description = "{{DISPLAY_NAME}}"
requires-python = ">={{PYTHON_MINOR}}"
dependencies = []

[build-system]
requires = ["setuptools>=75"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]
