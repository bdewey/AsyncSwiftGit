#import "git2.h"

__attribute__((constructor))
static void AsyncSwiftGitInit(void) {
  git_libgit2_init();
}

