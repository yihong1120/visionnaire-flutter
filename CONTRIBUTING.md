# Contributing

Thank you for improving Visionnaire.

## Before opening a pull request

1. Do not include credentials, production endpoints, Firebase project files, signing material, captured media, customer data, or real user data.
2. Put deployment-specific values in ignored local configuration files only.
3. Keep domain models and transport payloads explicitly typed at API boundaries; do not add untyped fallback parsing for a known contract.
4. Run `dart format`, `flutter analyze`, relevant tests, and `git diff --check`.
5. Explain any API-contract or platform-configuration change in the pull request description.

## Tests

Use generic fixtures such as `Site A`, `Cam 1`, and `Example User`. Never add real site names, camera identifiers, account names, email addresses, tokens, or production URLs to a test.

## Licence and contribution authority

Only contribute code that you are authorized to license under the repository's
licence terms. By submitting a contribution, you confirm that it may be
distributed under the GNU General Public License version 2 only, unless the
maintainers explicitly agree otherwise in writing.
