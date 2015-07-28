#!/bin/bash
#
# Entry point for tests
.  test_functions

Test passthrough-success
Test passthrough-failure
Test expand-env

FinishTests
