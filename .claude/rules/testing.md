# Testing

After any code change, run `make test` from the project root and all tests must pass before considering the task complete.

Each test must be stateless and self-contained. Use `after_each` to clean up buffers via `h.clean_bufs()`. Never share mutable state between tests.

Every public function needs tests covering: happy path, edge cases (empty input, no comment syntax), and failure cases.

Prefer naming local variables before asserting:
- Input: `input`
- Expected: `expected`
- Actual: `actual`

Test files live in `tests/cbox/` and must be named `*_spec.lua`.
