'use strict';

// This legacy utility previously reset the remote administrator password to a
// built-in value. Keep the filename for old operational references, but refuse
// to perform database writes.
if (require.main === module) {
  console.error('Disabled: use the approved administrator password recovery flow.');
  process.exitCode = 1;
}