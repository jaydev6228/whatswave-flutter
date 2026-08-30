# Contributing

**Please read the [LICENSE](../LICENSE) first.** This project is source
available, not open source. The code may be read; it may not be reused.

## What is welcome

- **Bug reports.** Steps to reproduce, what you expected, what happened,
  and the device/OS if it is a UI issue.
- **Questions** about how something works.

## What is not

Pull requests are generally **not accepted**. This is a personal project
with a specific direction, and merging outside contributions would raise
licensing questions the project is not set up to answer.

If you have found a bug and know the fix, describe it in an issue — that
is genuinely useful, and faster for both of us than a PR neither of us
can merge.

## If a change is invited

Should the maintainer ask you to open a PR:

```bash
flutter analyze          # must be clean
flutter test             # must pass
dart format lib/ test/   # must produce no changes
```

Match the surrounding code — its naming, its comment density, its idiom.
Comments should explain *why*, not restate *what*.

UI changes must follow [`docs/ui_layout_guidelines.md`](../docs/ui_layout_guidelines.md),
including testing at the narrowest supported width crossed with the
largest font scale.
