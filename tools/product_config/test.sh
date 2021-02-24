#!/bin/bash

#
# This script runs the full set of tests for product config:
# 1. Build the product-config tool.
# 2. Run the unit tests.
# 3. Run the product config for every product available in the current
#    source tree, for each of user, userdebug and eng.
#       - To restrict which products or variants are run, set the
#         PRODUCTS or VARIANTS environment variables.
#       - Products for which the make based product config fails are
#         skipped.
#

# The PRODUCTS variable is used by the build, and setting it in the environment
# interferes with that, so unset it.  (That should probably be fixed)
products=$PRODUCTS
variants=$VARIANTS
unset PRODUCTS
unset VARIANTS

# Don't use lunch from the user's shell
unset TARGET_PRODUCT
unset TARGET_BUILD_VARIANT

function die() {
    format=$1
    shift
    printf "$format\nStopping...\n" $@ >&2
    exit 1;
}

[[ -f build/make/envsetup.sh ]] || die "Run this script from the root of the tree."
: ${products:=$(build/soong/soong_ui.bash --dumpvar-mode all_named_products | sed -e "s/ /\n/g" | sort -u )}
: ${variants:="user userdebug eng"}
: ${CKATI_BIN:=prebuilts/build-tools/$(build/soong/soong_ui.bash --dumpvar-mode HOST_PREBUILT_TAG)/bin/ckati}

function if_signal_exit() {
    [[ $1 -lt 128 ]] || exit $1
}

build/soong/soong_ui.bash --build-mode --all-modules --dir="$(pwd)" product-config-test product-config \
    || die "Build failed."

echo
echo Running unit tests
java -jar out/host/linux-x86/testcases/product-config-test/product-config-test.jar
unit_tests=$?
if_signal_exit $unit_tests

failed_baseline_checks=
for product in $products ; do
    for variant in $variants ; do
        echo
        echo Checking to see if $product-$variant works with make
        TARGET_PRODUCT=$product TARGET_BUILD_VARIANT=$variant build/soong/soong_ui.bash --dumpvar-mode TARGET_PRODUCT &> /dev/null
        exit_status=$?
        if_signal_exit $exit_status
        if [ $exit_status -ne 0 ] ; then
            echo Combo fails with make, skipping product-config test run for $product-$variant
        else
            echo Running product-config for $product-$variant
            rm -rf out/config/$product-$variant
            TARGET_PRODUCT=$product TARGET_BUILD_VARIANT=$variant product-config \
                            --ckati_bin $CKATI_BIN \
                            --error 1000
            exit_status=$?
            if_signal_exit $exit_status
            if [ $exit_status -ne 0 ] ; then
                failed_baseline_checks="$failed_baseline_checks $product-$variant"
            fi
        fi
    done
done

echo
echo
echo "------------------------------"
echo SUMMARY
echo "------------------------------"

echo -n "Unit tests        "
if [ $unit_tests -eq 0 ] ; then echo PASSED ; else echo FAILED ; fi

echo -n "Baseline checks   "
if [ "$failed_baseline_checks" = "" ] ; then echo PASSED ; else echo FAILED ; fi
for combo in $failed_baseline_checks ; do
    echo "                   ... $combo"
done

