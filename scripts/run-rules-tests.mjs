// Runs the security-rules suite against the Firebase emulators.
//
// Exists only to find a JDK. The Firestore and Storage emulators are Java
// programs, and `java` is frequently not on PATH on a macOS Flutter machine
// even though a perfectly good JDK is already installed -- Android Studio
// bundles one (JetBrains Runtime), which is the same JDK `flutter doctor`
// finds for Gradle builds. Requiring a separate `brew install openjdk`
// before the security tests can run is how a security suite quietly stops
// being run at all.
//
// Resolution order, first hit wins:
//   1. JAVA_HOME, if it actually contains bin/java (CI usually sets this)
//   2. `java` already on PATH
//   3. macOS /usr/libexec/java_home
//   4. Android Studio's bundled JetBrains Runtime
//
// Usage: npm run test:rules   (optionally: npm run test:rules -- --test-name-pattern=...)

import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const candidates = [];

if (process.env.JAVA_HOME) {
  candidates.push(process.env.JAVA_HOME);
}

if (spawnSync('java', ['-version'], { stdio: 'ignore' }).status === 0) {
  candidates.push(null); // already on PATH; nothing to add
}

if (process.platform === 'darwin') {
  const resolved = spawnSync('/usr/libexec/java_home', [], { encoding: 'utf8' });
  if (resolved.status === 0) {
    candidates.push(resolved.stdout.trim());
  }
  candidates.push('/Applications/Android Studio.app/Contents/jbr/Contents/Home');
}

const javaHome = candidates.find(
  (home) => home === null || (home && existsSync(join(home, 'bin', 'java'))),
);

if (javaHome === undefined) {
  console.error(
    [
      'No Java runtime found, and the Firestore/Storage emulators need one.',
      '',
      'Fix any one of these:',
      '  * install a JDK:            brew install openjdk',
      '  * point at an existing one: export JAVA_HOME=/path/to/jdk',
      '  * install Android Studio, whose bundled JDK is picked up automatically',
    ].join('\n'),
  );
  process.exit(1);
}

const env = { ...process.env };
if (javaHome !== null) {
  env.JAVA_HOME = javaHome;
  env.PATH = `${join(javaHome, 'bin')}:${env.PATH}`;
}

const passthrough = process.argv.slice(2);
// An explicit glob, not a bare directory: Node 26's --test resolves a
// directory argument as a module path and dies with MODULE_NOT_FOUND.
const nodeTest = ['node', '--test', 'test/rules/*.test.mjs', ...passthrough]
  .map((part) => (part.includes(' ') ? JSON.stringify(part) : part))
  .join(' ');

const child = spawn(
  'firebase',
  [
    'emulators:exec',
    '--project',
    'demo-whatswave',
    '--config',
    'firebase.test.json',
    '--only',
    'firestore,storage',
    nodeTest,
  ],
  { stdio: 'inherit', env },
);

child.on('exit', (code, signal) => {
  process.exit(signal ? 1 : (code ?? 1));
});
