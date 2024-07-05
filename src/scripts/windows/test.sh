#!/bin/false
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016

trap_exit() {
  local exit_status="$?"

  if [ "$exit_status" -ne 0 ]; then
    printf '%s\n' 'The script did not complete successfully.'

    printf '%s\n' "Removing the container \"$CONTAINER_NAME\"."
    docker rm -f "$CONTAINER_NAME" &> /dev/null || true

    exit "$exit_status"
  fi
}
trap trap_exit EXIT

# Add necessary values in the environment variables.
docker exec "$CONTAINER_NAME" powershell "[System.Environment]::SetEnvironmentVariable('TEST_PLATFORM','$PARAM_TEST_PLATFORM', [System.EnvironmentVariableTarget]::Machine)"
docker exec "$CONTAINER_NAME" powershell "[System.Environment]::SetEnvironmentVariable('CUSTOM_PARAMS','$custom_parameters', [System.EnvironmentVariableTarget]::Machine)"

test_args=(
  '-batchmode'
  '-nographics'
  '-projectPath $Env:PROJECT_PATH'
  '-runTests'
  '-testPlatform $Env:TEST_PLATFORM'
  '-testResults "C:/test/results.xml"'
)

[ -n "$custom_parameters" ] && test_args+=( '$Env:CUSTOM_PARAMS.split()' )

# Run the tests.
set -x
docker exec "$CONTAINER_NAME" powershell -Command "
\$unityExe = 'C:\UnityEditor\' + \$Env:UNITY_VERSION + '\Editor\Unity.exe';
& \$unityExe ${test_args[*]} -logfile | Out-Host
"
set +x

# Install JDK to run Saxon.
docker exec "$CONTAINER_NAME" powershell 'choco upgrade jdk8 --no-progress -y'

# Download and extract Saxon-B.
docker exec "$CONTAINER_NAME" powershell 'Invoke-WebRequest -Uri "https://versaweb.dl.sourceforge.net/project/saxon/Saxon-B/9.1.0.8/saxonb9-1-0-8j.zip" -Method "GET" -OutFile "C:/test/saxonb.zip"'
docker exec "$CONTAINER_NAME" powershell "Expand-Archive -Force C:/test/saxonb.zip C:/test/saxonb"

# Copy the Saxon-B template to the container.
printf '%s\n' "$DEPENDENCY_NUNIT_TRANSFORM" > "$base_dir/test/nunit3-junit.xslt"

# Parse Unity's results xml to JUnit format.
docker exec "$CONTAINER_NAME" powershell 'java -jar C:/test/saxonb/saxon9.jar -s C:/test/results.xml -xsl C:/test/nunit3-junit.xslt > C:/test/junit-results.xml'

# Convert CRLF to LF otherwise CircleCI won't be able to read the results.
# https://stackoverflow.com/a/48919146
docker exec "$CONTAINER_NAME" powershell '((Get-Content C:/test/junit-results.xml) -join "`n") + "`n" | Set-Content -NoNewline -Encoding utf8 C:/test/junit-results-lf.xml'

# Move test results to project folder for upload.
mv "$base_dir"/test/junit-results-lf.xml "$unity_project_full_path"/"$PARAM_TEST_PLATFORM"-junit-results.xml
