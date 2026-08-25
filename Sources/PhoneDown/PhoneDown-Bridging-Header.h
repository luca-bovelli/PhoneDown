// notify.h is not part of the Darwin module Swift imports, so the notify_*
// family has to be bridged in explicitly. It is the only way to read the *state*
// of a Darwin notification: CFNotificationCenter's Darwin centre tells you that
// a key fired but not what it changed to, which for displayStatus is the entire
// piece of information — on versus off.

#import <notify.h>
