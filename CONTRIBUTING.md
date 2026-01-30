# Contributing

Thank you for helping improve the AlmaLinux M&E Hardware Survey.

## For users submitting reports
Please follow the steps in `README.md` and use the issue form to submit your JSON output.

## For maintainers

### Approving a report
1. Open the issue and confirm it includes valid JSON.
2. Add the `approved` label to the issue.
3. The GitHub Action generates:
   - `data/reports/<id>.json`
   - `docs/results/<id>/index.md`
   and opens a PR.
4. The action comments on the issue with a PR link.
5. Review and merge the PR.
6. On merge, another action comments and closes the issue.

### Common problems and fixes
- **Missing JSON block:** ask the user to paste the full JSON output again.
- **Invalid JSON:** request re-run of the script and re-submit.
- **Sensitive data included:** ask the user to remove it and resubmit.

### Labels required
- `hardware-report` (from the issue template)
- `approved` (maintainer applied to trigger the workflow)

### Publishing the website
- GitHub Pages works on public repos (or paid plans for private).
- Merges to `main` trigger MkDocs publishing via GitHub Actions.

## License
By contributing, you agree your contributions are licensed under GPLv3 (see `LICENSE`).
