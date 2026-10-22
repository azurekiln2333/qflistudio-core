# Design

Keep filtering at the local content page/model adapter boundary. Add optional metadata to TutorialLesson and ExampleCode; retain existing constructors/defaults and saved-example storage compatibility. Filter immutable loaded rows in UI without refetching assets. Derive supported language choices from actual loaded content and profile; normalize C++ labels. Keep lazy list construction and avoid per-row repository work.

Use one shared language badge component styled consistently with project cards. Preserve content title sizing and narrow layouts. No extra navigation, network calls or changes to product runtime interfaces.

Exclusive worker owns local content pages, adapter, lesson/example metadata, saved example serialization, badge widget/project-card reuse and focused tests only. Explorer/history and diagnostic APIs are reserved for separate owners. Revert only owned paths if needed.
