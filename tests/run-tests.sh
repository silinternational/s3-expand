#!/bin/bash
#
# Entry point for tests
.  test_functions

Test passthrough-success
Test passthrough-failure

Test convert-loop

Test expand-env

Test s3-files

FinishTests
