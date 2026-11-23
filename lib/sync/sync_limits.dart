/// Size limits shared by the device sync paths.
///
/// One place keeps the agent, the sync service and the cache in step: a limit
/// changed here changes every layer in the same build.
library;

/// A clone is confirmed by the user before it starts when the `.git` directory
/// on the computer is larger than this.
///
/// The count comes from `project_git_info.gitBytes`, so it signals the download
/// size; it is not the exact number of bytes the phone will receive.
const int kGitConfirmBytes = 200 * 1024 * 1024;
