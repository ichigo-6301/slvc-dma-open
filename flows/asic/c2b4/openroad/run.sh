#!/usr/bin/env bash
set -euo pipefail

: "${DMA_C4_REG_ROOT:?Missing DMA_C4_REG_ROOT}"
: "${DMA_C4_REG_BUILD_ROOT:?Missing DMA_C4_REG_BUILD_ROOT}"
: "${DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ:?Missing DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ}"
: "${DMA_C4_REG_MAPPED_SOURCE_CLOCK_PERIOD_NS:?Missing DMA_C4_REG_MAPPED_SOURCE_CLOCK_PERIOD_NS}"
: "${DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ:?Missing DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ}"
: "${DMA_C4_REG_CLOCK_PERIOD_NS:?Missing DMA_C4_REG_CLOCK_PERIOD_NS}"
: "${DMA_C4_REG_MAPPED_NETLIST:?Missing DMA_C4_REG_MAPPED_NETLIST}"
: "${DMA_C4_REG_SDC:?Missing DMA_C4_REG_SDC}"
: "${DMA_C4_REG_ORFS_IMAGE:?Missing DMA_C4_REG_ORFS_IMAGE}"
: "${DMA_C4_REG_ORFS_COMMIT:?Missing DMA_C4_REG_ORFS_COMMIT}"
: "${DMA_C4_REG_DESIGN_NAME:?Missing DMA_C4_REG_DESIGN_NAME}"
: "${DMA_C4_REG_HANDOFF_BASENAME:?Missing DMA_C4_REG_HANDOFF_BASENAME}"
: "${DMA_C4_REG_DESIGN_NICKNAME:?Missing DMA_C4_REG_DESIGN_NICKNAME}"
: "${DMA_C4_REG_EXPECTED_INPUT_PORTS:?Missing DMA_C4_REG_EXPECTED_INPUT_PORTS}"
: "${DMA_C4_REG_EXPECTED_OUTPUT_PORTS:?Missing DMA_C4_REG_EXPECTED_OUTPUT_PORTS}"
: "${DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS:?Missing DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS}"
: "${DMA_C4_REG_HOLD_UNCERTAINTY_NS:?Missing DMA_C4_REG_HOLD_UNCERTAINTY_NS}"
: "${DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS:?Missing DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS}"

[[ "$DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS" == "0.000" ]] || {
  echo "Global-route hold margin must be exactly 0.000 ns" >&2; exit 2;
}

[[ "$DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ" =~ ^[0-9]+$ ]] || {
  echo "Mapped source frequency must be an integer" >&2; exit 2;
}
[[ "$DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ" =~ ^[0-9]+$ ]] || {
  echo "Physical frequency must be an integer" >&2; exit 2;
}
(( DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ <= DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ )) || {
  echo "Physical frequency exceeds mapped DC source frequency" >&2; exit 2;
}

resume_from_cts=${DMA_C4_REG_RESUME_FROM_CTS:-0}
[[ "$resume_from_cts" == 0 || "$resume_from_cts" == 1 ]] || {
  echo "DMA_C4_REG_RESUME_FROM_CTS must be 0 or 1" >&2; exit 2;
}
resume_reason=${DMA_C4_REG_RESUME_REASON:-}
if [[ "$resume_from_cts" == 0 && -n "$resume_reason" ]]; then
  echo "DMA_C4_REG_RESUME_REASON requires CTS resume" >&2; exit 2;
fi

expected_orfs_commit=bea7dcd7be7f26d1328f6058b01cf42bf4352aa2
expected_image='openroad/orfs@sha256:5fb6465e18c42bfaa19f0ba40190f1c75cb6118feffd236b13ed8081ff3f573f'
expected_liberty_sha=8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1
[[ "$DMA_C4_REG_ORFS_COMMIT" == "$expected_orfs_commit" ]] || {
  echo "ORFS commit mismatch" >&2; exit 2;
}
[[ "$DMA_C4_REG_ORFS_IMAGE" == "$expected_image" ]] || {
  echo "ORFS container mismatch" >&2; exit 2;
}
[[ "$DMA_C4_REG_BUILD_ROOT" == "$DMA_C4_REG_ROOT"/* ]] || {
  echo "Build root must be inside the repository" >&2; exit 2;
}
test -s "$DMA_C4_REG_MAPPED_NETLIST"
test -s "$DMA_C4_REG_SDC"
pre_route_audit="$DMA_C4_REG_ROOT/flows/asic/c2b4/openroad/pre_global_route_audit.tcl"
sdc_audit="$DMA_C4_REG_ROOT/flows/asic/c2b4/openroad/audit_physical_sdc.py"
test -s "$pre_route_audit"
test -s "$sdc_audit"

attempt_id="dc${DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ}mhz_pnr${DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ}mhz"
attempt="$DMA_C4_REG_BUILD_ROOT/openroad/attempts/$attempt_id"
work_home="$attempt/orfs"
handoff="$attempt/handoff"
mkdir -p "$work_home" "$handoff"
contract="$attempt/run_contract.txt"
candidate="$attempt/run_contract.candidate"
threads=$(nproc)
liberty="$DMA_C4_REG_ROOT/flows/local/nangate45/NangateOpenCellLibrary_typical.lib"
if [[ -s "$liberty" ]]; then
  actual_liberty_sha=$(sha256sum "$liberty" | awk '{print $1}')
  [[ "$actual_liberty_sha" == "$expected_liberty_sha" ]] || {
    echo "Local Nangate45 Liberty hash mismatch" >&2; exit 2;
  }
fi
{
  echo "synthesis_tool=dc_shell_O-2018.06-SP1"
  echo "synthesis_command=compile_ultra"
  echo "orfs_commit=$DMA_C4_REG_ORFS_COMMIT"
  echo "orfs_image=$DMA_C4_REG_ORFS_IMAGE"
  echo "mapped_source_frequency_mhz=$DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ"
  echo "mapped_source_clock_period_ns=$DMA_C4_REG_MAPPED_SOURCE_CLOCK_PERIOD_NS"
  echo "physical_frequency_mhz=$DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ"
  echo "physical_clock_period_ns=$DMA_C4_REG_CLOCK_PERIOD_NS"
  echo "clock_period_tolerance_ns=$DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS"
  echo "physical_hold_uncertainty_ns=$DMA_C4_REG_HOLD_UNCERTAINTY_NS"
  if [[ "$DMA_C4_REG_HOLD_UNCERTAINTY_NS" == "0.000" ]]; then
    echo "physical_hold_methodology=ideal_nominal_no_ocv_or_jitter"
  else
    echo "physical_hold_methodology=explicit_hold_uncertainty"
  fi
  echo "design_name=$DMA_C4_REG_DESIGN_NAME"
  echo "handoff_basename=$DMA_C4_REG_HANDOFF_BASENAME"
  echo "expected_nonclock_input_ports=$DMA_C4_REG_EXPECTED_INPUT_PORTS"
  echo "expected_output_ports=$DMA_C4_REG_EXPECTED_OUTPUT_PORTS"
  echo "cts_hold_slack_margin_ns=0.060"
  echo "global_route_hold_slack_margin_ns=$DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS"
  echo "threads=$threads"
  echo "nangate45_liberty_sha256=$expected_liberty_sha"
  echo "mapped_netlist_sha256=$(sha256sum "$DMA_C4_REG_MAPPED_NETLIST" | awk '{print $1}')"
  echo "sdc_sha256=$(sha256sum "$DMA_C4_REG_SDC" | awk '{print $1}')"
  echo "config_sha256=$(sha256sum "$DMA_C4_REG_ROOT/flows/asic/c2b4/openroad/config.mk" | awk '{print $1}')"
  echo "run_script_sha256=$(sha256sum "$DMA_C4_REG_ROOT/flows/asic/c2b4/openroad/run.sh" | awk '{print $1}')"
  echo "pre_global_route_audit_sha256=$(sha256sum "$pre_route_audit" | awk '{print $1}')"
  echo "physical_sdc_audit_sha256=$(sha256sum "$sdc_audit" | awk '{print $1}')"
} > "$candidate"

contract_field() {
  local file=$1
  local key=$2
  awk -F= -v key="$key" '
    $1 == key { count += 1; value = substr($0, index($0, "=") + 1) }
    END { if (count != 1) exit 2; print value }
  ' "$file"
}

if [[ -e "$contract" ]]; then
  if [[ "$resume_from_cts" == 1 ]]; then
    for key in synthesis_tool synthesis_command orfs_commit orfs_image \
      mapped_source_frequency_mhz mapped_source_clock_period_ns \
      physical_frequency_mhz physical_clock_period_ns \
      clock_period_tolerance_ns \
      physical_hold_uncertainty_ns physical_hold_methodology \
      design_name handoff_basename expected_nonclock_input_ports \
      expected_output_ports threads \
      nangate45_liberty_sha256 mapped_netlist_sha256 sdc_sha256 \
      physical_sdc_audit_sha256; do
      old_value=$(contract_field "$contract" "$key") || {
        echo "Original run contract omits unique field: $key" >&2; exit 2;
      }
      new_value=$(contract_field "$candidate" "$key") || {
        echo "Resume run contract omits unique field: $key" >&2; exit 2;
      }
      [[ "$old_value" == "$new_value" ]] || {
        echo "Resume input mismatch for $key" >&2; exit 2;
      }
    done
    cts_odb="$work_home/results/nangate45/$DMA_C4_REG_DESIGN_NICKNAME/base/4_cts.odb"
    cts_sdc="$work_home/results/nangate45/$DMA_C4_REG_DESIGN_NICKNAME/base/4_cts.sdc"
    failure_log="$DMA_C4_REG_BUILD_ROOT/resources/pnr_${attempt_id}.log"
    test -s "$cts_odb"
    test -s "$cts_sdc"
    test -s "$failure_log"
    case "$resume_reason" in
      drt_constant_net_v1)
        grep -Fq 'DRT-0305' "$failure_log"
        grep -Fq 'not routable by TritonRoute' "$failure_log"
        ;;
      grt_hold_margin_split_v1)
        grep -Fq 'repair_timing -setup_margin 0.0 -hold_margin 0.06' "$failure_log"
        grep -Eq 'Found [1-9][0-9]* endpoints with hold violations' "$failure_log"
        grep -Fq 'Terminated' "$failure_log"
        ;;
      *)
        echo "Unsupported or missing CTS resume reason: $resume_reason" >&2
        exit 2
        ;;
    esac
    resume_candidate="$attempt/resume_contract.candidate"
    resume_contract="$attempt/resume_contract.txt"
    cp "$candidate" "$resume_candidate"
    {
      echo "resume_from_cts=1"
      echo "resume_reason=$resume_reason"
      echo "resume_parent_contract_sha256=$(sha256sum "$contract" | awk '{print $1}')"
      echo "resume_failure_log_sha256=$(sha256sum "$failure_log" | awk '{print $1}')"
      echo "resume_cts_odb_sha256=$(sha256sum "$cts_odb" | awk '{print $1}')"
      echo "resume_cts_sdc_sha256=$(sha256sum "$cts_sdc" | awk '{print $1}')"
    } >> "$resume_candidate"
    if [[ -e "$resume_contract" ]]; then
      cmp -s "$resume_contract" "$resume_candidate" || {
        echo "Existing CTS resume contract differs" >&2; exit 2;
      }
      rm -f "$resume_candidate"
    else
      mv "$resume_candidate" "$resume_contract"
    fi
    rm -f "$candidate"
  else
    cmp -s "$contract" "$candidate" || {
      echo "Existing ORFS workspace has a different run contract" >&2
      rm -f "$candidate"
      exit 2
    }
    rm -f "$candidate"
  fi
else
  [[ "$resume_from_cts" == 0 ]] || {
    echo "Cannot resume CTS without an original run contract" >&2
    rm -f "$candidate"
    exit 2
  }
  if find "$work_home" -mindepth 1 -print -quit | grep -q .; then
    echo "Existing ORFS workspace has no run contract" >&2
    rm -f "$candidate"
    exit 2
  fi
  mv "$candidate" "$contract"
fi

container_path() {
  case "$1" in
    "$DMA_C4_REG_ROOT"/*) printf '/dma/%s' "${1#"$DMA_C4_REG_ROOT"/}" ;;
    *) echo "ORFS input is outside DMA_C4_REG_ROOT: $1" >&2; return 2 ;;
  esac
}

container_netlist=$(container_path "$DMA_C4_REG_MAPPED_NETLIST")
container_sdc=$(container_path "$DMA_C4_REG_SDC")
container_build=$(container_path "$DMA_C4_REG_BUILD_ROOT")
docker_tool=${DMA_C4_REG_DOCKER:-docker}
container_name="dma-c4-reg-pnr-${attempt_id}"
make_targets=
if [[ "$resume_from_cts" == 1 ]]; then
  container_name="${container_name}-resume-cts"
  make_targets="do-route do-finish"
fi
results="$work_home/results/nangate45/$DMA_C4_REG_DESIGN_NICKNAME/base"

if ! { test -s "$results/6_final.odb" && test -s "$results/6_final.v" && \
       test -s "$results/6_final.sdc" && test -s "$results/6_final.spef"; }; then
  if "$docker_tool" ps -a --format '{{.Names}}' | grep -Fxq "$container_name"; then
    echo "Existing ORFS container must be inspected: $container_name" >&2
    exit 2
  fi
  uid=$(id -u)
  gid=$(id -g)
  "$docker_tool" run --rm --name "$container_name" \
    -u "$uid:$gid" -v "$DMA_C4_REG_ROOT:/dma" \
    -e DMA_C4_REG_ROOT=/dma \
    -e DMA_C4_REG_BUILD_ROOT="$container_build" \
    -e DMA_C4_REG_MAPPED_NETLIST="$container_netlist" \
    -e DMA_C4_REG_SDC="$container_sdc" \
    -e DMA_C4_REG_DESIGN_NAME="$DMA_C4_REG_DESIGN_NAME" \
    -e DMA_C4_REG_DESIGN_NICKNAME="$DMA_C4_REG_DESIGN_NICKNAME" \
    -e DMA_C4_REG_CLOCK_PERIOD_NS="$DMA_C4_REG_CLOCK_PERIOD_NS" \
    -e DMA_C4_REG_SETUP_UNCERTAINTY_NS=0.200 \
    -e DMA_C4_REG_HOLD_UNCERTAINTY_NS="$DMA_C4_REG_HOLD_UNCERTAINTY_NS" \
    -e DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS="$DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS" \
    -e DMA_C4_REG_EXPECTED_INPUT_PORTS="$DMA_C4_REG_EXPECTED_INPUT_PORTS" \
    -e DMA_C4_REG_EXPECTED_OUTPUT_PORTS="$DMA_C4_REG_EXPECTED_OUTPUT_PORTS" \
    -e DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS="$DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS" \
    -e DMA_C4_REG_THREADS="$threads" \
    -e DMA_C4_REG_EXPECTED_LIBERTY_SHA="$expected_liberty_sha" \
    -e DMA_C4_REG_MAKE_TARGETS="$make_targets" \
    -w /OpenROAD-flow-scripts/flow "$DMA_C4_REG_ORFS_IMAGE" \
    bash -lc 'set -e; lib=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib; test "$(sha256sum "$lib" | awk '\''{print $1}'\'')" = "$DMA_C4_REG_EXPECTED_LIBERTY_SHA"; source /OpenROAD-flow-scripts/env.sh; work="$DMA_C4_REG_BUILD_ROOT/openroad/attempts/'"$attempt_id"'/orfs"; if [[ -z "$DMA_C4_REG_MAKE_TARGETS" ]]; then make DESIGN_CONFIG=/dma/flows/asic/c2b4/openroad/config.mk WORK_HOME="$work" synth; fi; python3 /dma/flows/asic/c2b4/openroad/audit_physical_sdc.py --sdc "$work/results/nangate45/$DMA_C4_REG_DESIGN_NICKNAME/base/1_synth.sdc" --log "$work/logs/nangate45/$DMA_C4_REG_DESIGN_NICKNAME/base/1_synth.log" --period "$DMA_C4_REG_CLOCK_PERIOD_NS" --period-tolerance "$DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS" --setup-uncertainty "$DMA_C4_REG_SETUP_UNCERTAINTY_NS" --hold-uncertainty "$DMA_C4_REG_HOLD_UNCERTAINTY_NS" --expected-input-count "$DMA_C4_REG_EXPECTED_INPUT_PORTS" --expected-output-count "$DMA_C4_REG_EXPECTED_OUTPUT_PORTS"; make DESIGN_CONFIG=/dma/flows/asic/c2b4/openroad/config.mk WORK_HOME="$work" $DMA_C4_REG_MAKE_TARGETS'
fi

for suffix in odb v sdc spef; do
  test -s "$results/6_final.$suffix" || {
    echo "Missing same-run ORFS artifact: 6_final.$suffix" >&2; exit 2;
  }
done
synth_copy="$results/1_2_yosys.v"
# 1_2_yosys.v is ORFS's fixed handoff filename even when synthesis was DC.
test -s "$synth_copy" || { echo "Missing ORFS DC mapped-netlist copy" >&2; exit 2; }
[[ "$(sha256sum "$synth_copy" | awk '{print $1}')" == \
   "$(sha256sum "$DMA_C4_REG_MAPPED_NETLIST" | awk '{print $1}')" ]] || {
  echo "ORFS remapped or changed the DC mapped netlist" >&2; exit 2;
}

cp "$results/6_final.odb" "$handoff/${DMA_C4_REG_HANDOFF_BASENAME}_postroute.odb"
cp "$results/6_final.v" "$handoff/${DMA_C4_REG_HANDOFF_BASENAME}_postroute.v"
python3 "$DMA_C4_REG_ROOT/flows/asic/c2b4/openroad/sanitize_openroad_sdc.py" \
  --input "$results/6_final.sdc" \
  --output "$handoff/${DMA_C4_REG_HANDOFF_BASENAME}_postroute.sdc"
cp "$results/6_final.spef" "$handoff/${DMA_C4_REG_HANDOFF_BASENAME}_postroute.spef"
(cd "$handoff" && sha256sum \
  "${DMA_C4_REG_HANDOFF_BASENAME}_postroute.odb" \
  "${DMA_C4_REG_HANDOFF_BASENAME}_postroute.v" \
  "${DMA_C4_REG_HANDOFF_BASENAME}_postroute.sdc" \
  "${DMA_C4_REG_HANDOFF_BASENAME}_postroute.spef" > sha256.txt)
echo "DMA_C4_REGISTER_OPENROAD_HANDOFF_PASS mapped_source_frequency_mhz=$DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ physical_frequency_mhz=$DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ"
