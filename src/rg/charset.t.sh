#!/usr/bin/env bash

(
    for DEC in {0..1114111}; do
        (
            printf -v HEX "%x" $DEC

            while [[ ${#HEX} -lt 8 ]]; do
                HEX="0${HEX}"
            done

            printf -v C "\U$HEX"

            # Secondary character
            # eval "TEST_${HEX}_${C}_OK() { echo $HEX OK; }" > /dev/null 2>&1
            # set | grep -q "^TEST_${HEX}_._OK "

            # Leading character
            eval "${C}_TEST_${HEX}_OK() { echo $HEX OK; }" > /dev/null 2>&1
            set | grep -q "^._TEST_${HEX}_OK "

            if [[ $? -ne 0 ]]; then
                echo "INVALID: ${HEX}"
            fi
        )
    done
)