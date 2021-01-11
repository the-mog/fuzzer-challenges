#!/bin/bash
###################
### START OF CONFIG

# default fuzzer setup (afl++, honggfuzz, libfuzzer)
FUZZER=afl++

# how many seconds to try each testcase, recommended: 10-30
RUNTIME=120

# test a fuzzer in a specific directory? you can put that here
#FUZZER_DIR=~/AFLplusplus/branches/cmplog_variant

### END OF CONFIG
#################

# cmdline processing
test -z "$1" && { echo Warning: no target given - assuming afl++ - available: afl++, honggfuzz, libfuzzer; echo; }
test -n "$1" && FUZZER=$1
DONE=

# fuzzer options
test "$FUZZER" = "afl++" && { 
  export CC=afl-clang-fast
  export CXX=afl-clang-fast++
  export AFL_LLVM_CMPLOG=1
  DONE=1
}
test "$FUZZER" = "libfuzzer" && { 
  export CC=clang
  export CXX=clang++
  export CFLAGS="-fsanitize=fuzzer -fsanitize=address"
  #counterproductive: -use_value_profile=1
  export FUZZER_OPTIONS="-entropic=1 $FUZZER_OPTIONS"
  DONE=1
}
test "$FUZZER" = "honggfuzz" && {
  export CC=hfuzz-clang
  export CXX=hfuzz-clang++
  DONE=1
}

test -z "$DONE" && { echo Error: invalid fuzzer, allowed are only afl++, libfuzzer or honggfuzz; exit 1; }
echo Fuzzer: $FUZZER
echo Maximum runtime: $RUNTIME
echo

# prepare environment
echo Preparation:
echo CC=$CC
echo CFLAGS=$CFLAGS
env|grep AFL_
export CXXFLAGS="$CFLAGS $CXXFLAGS"
export AFL_QUIET=1
make clean >/dev/null 2>&1
make compile || exit 1
rm -rf in out-* *.log crash* SIG* HONGGFUZZ.REPORT.TXT
ulimit -c 0
mkdir in || exit 1
echo ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ > in/in
test "$FUZZER" = "afl++" && {
  OK=
  afl-fuzz -h 2>&1 | grep -q ' -l ' && OK=1
  test -z "$OK" && echo Warning: afl++ is not cmplog_variant
  test -n "$OK" && FUZZER_OPTIONS="-l 3 $FUZZER_OPTIONS"
}

# set envs
export AFL_NO_UI=1
export AFL_BENCH_UNTIL_CRASH=1
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export RUNTIME
unset ASAN_FUZZER_OPTIONS
export ASAN_OPTIONS="disable_coredump=0:unmap_shadow_on_exit=1:abort_on_error=1:detect_leaks=0:symbolize=0"
test -n "$FUZZER_DIR" && export PATH=$FUZZER_DIR:$PATH
test -n "$FUZZER_DIR" && export AFL_PATH=$FUZZER_DIR
SUCCESS=0
FAIL=0
echo
echo Starting tests
echo Fuzzer special options: $FUZZER_OPTIONS

# run test cases
for i in *.c*; do
  TARGET=${i//\.c*/}
  test -x "$TARGET" && {
    echo Running $TARGET ...

    test "$FUZZER" = afl++ && {
      TIME=`{ time afl-fuzz $FUZZER_OPTIONS -V$RUNTIME -i in -o out-$TARGET -c ./$TARGET -- ./$TARGET >/dev/null 2>$TARGET.log ; } 2>&1 |grep -w real|awk '{print$2}'`
      ls out-$TARGET/default/crashes/id* >/dev/null 2>&1 && {
        echo SUCCESS: $TARGET $TIME
        test -z "$NO_DELETE" && rm -rf out-$TARGET $TARGET.log
        SUCCESS=$((SUCCESS + 1))
      } || {
        echo FAIL: $TARGET
        ls out-$TARGET/default/queue
        echo 
        FAIL=$((FAIL + 1))
      }
    }

    test "$FUZZER" = honggfuzz && {
      cp -r in out-$TARGET
      TIME=`{ time honggfuzz $FUZZER_OPTIONS --run_time $RUNTIME -q --exit_upon_crash -i out-$TARGET -s -v -- ./$TARGET >/dev/null 2>$TARGET.log ; } 2>&1 |grep -w real|awk '{print$2}'`
      ls SIG* >/dev/null 2>&1 && {
        echo SUCCESS: $TARGET $TIME
        test -z "$NO_DELETE" && rm -rf out-$TARGET $TARGET.log
        rm -f SIG* HONGGFUZZ.REPORT.TXT 
        SUCCESS=$((SUCCESS + 1))
      } || {
        echo FAIL: $TARGET
        ls out-$TARGET/
        echo 
        FAIL=$((FAIL + 1))
      }
    }

    test "$FUZZER" = libfuzzer && {
      cp -r in out-$TARGET
      # -use_value_profile=1 decreases the performance
      TIME=`{ time ./$TARGET $FUZZER_OPTIONS -timeout=1 -detect_leaks=0 -max_total_time=$RUNTIME -workers=0 >/dev/null 2>$TARGET.log ; } 2>&1 |grep -w real|awk '{print$2}'`
      ls crash* >/dev/null 2>&1 && {
        echo SUCCESS: $TARGET $TIME
        test -z "$NO_DELETE" && rm -rf out-$TARGET $TARGET.log
        rm -f crash*
        SUCCESS=$((SUCCESS + 1))
      } || {
        echo FAIL: $TARGET
        ls out-$TARGET/
        echo 
        FAIL=$((FAIL + 1))
      }
    }

  }
done

echo "Done! SUCCESS=$SUCCESS FAIL=$FAIL"
