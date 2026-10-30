'use strict';

// Legacy credential-reset utility disabled to prevent accidental account writes.
if (require.main === module) {
  console.error('Disabled: use the approved administrator password recovery flow.');
  process.exitCode = 1;
}