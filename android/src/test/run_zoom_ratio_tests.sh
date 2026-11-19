#!/usr/bin/env bash
# DLCT: compile and run ZoomRatioTest on the JVM with kotlinc + JUnit, no Flutter host app or Gradle.
# ZoomRatio is pure Kotlin, so it is compiled on its own. Needs `kotlinc` and `java` on PATH.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
main_src="$here/../main/kotlin/com/apparence/camerawesome/utils/ZoomRatio.kt"
test_src="$here/kotlin/com/apparence/camerawesome/utils/ZoomRatioTest.kt"
out="$(mktemp -d)"
maven="https://repo1.maven.org/maven2"
curl -fsSL -o "$out/junit.jar" "$maven/junit/junit/4.13.2/junit-4.13.2.jar"
curl -fsSL -o "$out/hamcrest.jar" "$maven/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"
cp="$out/junit.jar:$out/hamcrest.jar"
kotlinc "$main_src" "$test_src" -cp "$cp" -include-runtime -d "$out/tests.jar" 2>&1 | grep -v '^warning:' || true
test -f "$out/tests.jar"
java -cp "$out/tests.jar:$cp" org.junit.runner.JUnitCore com.apparence.camerawesome.utils.ZoomRatioTest
