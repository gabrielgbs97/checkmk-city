#!/usr/bin/env python3
# Copyright (C) 2019 Checkmk GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.
# PATH (2.3): /omd/sites/<your_site>/local/lib/python3/cmk_addons/plugins/agent_vsphere_plus/agent_based/esx_vsphere_counters_gpu.py
import time
from collections.abc import Mapping, Sequence
from typing import Any

from cmk.utils import debug

from cmk.agent_based.v2 import (
    AgentSection,
    CheckPlugin,
    CheckResult,
    DiscoveryResult,
    get_value_store,
    IgnoreResultsError,
    RuleSetType,
    Service,
    StringTable,
    check_levels,
    render,
    Result,
    Metric,
    State
)
from cmk.plugins.lib import diskstat, esx_vsphere, interfaces
from cmk.plugins.lib.esx_vsphere import Section, SubSectionCounter
from cmk.plugins.lib.memory import check_element

# Example output:
# <<<esx_vsphere_counters:sep(124)>>>
# net.broadcastRx|vmnic0|11|number
# net.broadcastRx||11|number
# net.broadcastTx|vmnic0|0|number
# net.broadcastTx||0|number
# net.bytesRx|vmnic0|3820|kiloBytesPerSecond
# net.bytesRx|vmnic1|0|kiloBytesPerSecond
# net.bytesRx|vmnic2|0|kiloBytesPerSecond
# net.bytesRx|vmnic3|0|kiloBytesPerSecond
# net.bytesRx||3820|kiloBytesPerSecond
# net.bytesTx|vmnic0|97|kiloBytesPerSecond
# net.bytesTx|vmnic1|0|kiloBytesPerSecond
# net.bytesTx|vmnic2|0|kiloBytesPerSecond
# net.bytesTx|vmnic3|0|kiloBytesPerSecond
# net.bytesTx||97|kiloBytesPerSecond
# net.droppedRx|vmnic0|0|number
# net.droppedRx|vmnic1|0|number
# net.droppedRx|vmnic2|0|number
# net.droppedRx|vmnic3|0|number
# net.droppedRx||0|number
# net.droppedTx|vmnic0|0|number
# net.droppedTx|vmnic1|0|number
# ...
# datastore.read|4c4ece34-3d60f64f-1584-0022194fe902|0#1#2|kiloBytesPerSecond
# datastore.read|4c4ece5b-f1461510-2932-0022194fe902|0#4#5|kiloBytesPerSecond
# datastore.numberReadAveraged|511e4e86-1c009d48-19d2-bc305bf54b07|0#0#0|number
# datastore.numberWriteAveraged|4c4ece34-3d60f64f-1584-0022194fe902|0#0#1|number
# datastore.totalReadLatency|511e4e86-1c009d48-19d2-bc305bf54b07|0#5#5|millisecond
# datastore.totalWriteLatency|4c4ece34-3d60f64f-1584-0022194fe902|0#2#7|millisecond
# ...
# sys.uptime||630664|second


def parse_esx_vsphere_counters(string_table: StringTable) -> esx_vsphere.SectionCounter:
    """
    >>> from pprint import pprint
    >>> pprint(parse_esx_vsphere_counters([
    ... ['disk.numberReadAveraged', 'naa.5000cca05688e814', '0#0', 'number'],
    ... ['disk.write',
    ...  'naa.6000eb39f31c58130000000000000015',
    ...  '0#0',
    ...  'kiloBytesPerSecond'],
    ... ['net.bytesRx', 'vmnic0', '1#1', 'kiloBytesPerSecond'],
    ... ['net.droppedRx', 'vmnic1', '0#0', 'number'],
    ... ['net.errorsRx', '', '0#0', 'number'],
    ... ]))
    {'disk.numberReadAveraged': {'naa.5000cca05688e814': [(['0', '0'], 'number')]},
     'disk.write': {'naa.6000eb39f31c58130000000000000015': [(['0', '0'],
                                                              'kiloBytesPerSecond')]},
     'net.bytesRx': {'vmnic0': [(['1', '1'], 'kiloBytesPerSecond')]},
     'net.droppedRx': {'vmnic1': [(['0', '0'], 'number')]},
     'net.errorsRx': {'': [(['0', '0'], 'number')]}}
    """

    parsed: dict[str, dict[str, list[tuple[esx_vsphere.CounterValues, str]]]] = {}
    # The data reported by the ESX system is split into multiple real time samples with
    # a fixed duration of 20 seconds. A check interval of one minute reports 3 samples
    # The esx_vsphere_counters checks need to figure out by themselves how to handle this data
    for counter, instance, multivalues, unit in string_table:
        values = multivalues.split("#")
        parsed.setdefault(counter, {})
        parsed[counter].setdefault(instance, [])
        parsed[counter][instance].append((values, unit))
    return parsed


# .--GPU--------------------.
# |                         |
# |     ____ ____  _   _    |
# |    / ___|  _ \| | | |   |
# |   | |  _| |_) | | | |   |
# |   | |_| |  __/| |_| |   |
# |    \____|_|    \___/    |
# |                         |
# '-------------------------'

# Sample
# gpu.mem.reserved|000:003:00.0|318976|kiloBytes
# gpu.mem.total|000:003:00.0|23580672|kiloBytes
# gpu.mem.usage|000:003:00.0|135|percent
# gpu.mem.used|000:003:00.0|318976|kiloBytes
# gpu.power.used|000:003:00.0|21|watt
# gpu.temperature|000:003:00.0|35|celsius
# gpu.utilization|000:003:00.0|0|percent

def discover_esx_vsphere_counters_gpu_util(section: Section) -> DiscoveryResult:
    if debug.enabled():
      print("[plugin esx_vsphere_counters_gpu] ESX GPU service discovery called")
    for name, instances in section.items():
        if name == "gpu.utilization":
            for gpu_id, metrics in instances.items():
              if debug.enabled():
                print('Found gpu.utilization gpu_id=', gpu_id)
              yield Service(item=gpu_id)

def check_esx_vsphere_counters_gpu_util(
    item: str,
    params: Mapping[str, Any],
    section: Section,
) -> CheckResult:
    gpu_utilization = 0
    data = section.get("gpu.utilization", {}).get(item)
    multivalues, _unit = data[0] if data else (None, None)
    if multivalues is not None:
        gpu_utilization = int(multivalues[0]) / 100
        yield from check_levels(
            gpu_utilization,
            levels_upper=params.get("levels_upper", ("fixed", (80.0, 95.0))),
            render_func=render.percent,
            metric_name="esx_gpu_utilization",
            label="Utilization",
        )
    else:
        yield Result(state=State.UNKNOWN, summary="Gpu Utilization metric received but no values found")
    

check_plugin_esx_vsphere_gpu_util = CheckPlugin(
    name="esx_vsphere_counters_gpu_util",
    sections=["esx_vsphere_counters"],
    service_name="GPU Utilization %s",
    discovery_function=discover_esx_vsphere_counters_gpu_util,
    check_function=check_esx_vsphere_counters_gpu_util,
    check_default_parameters={"levels_upper": ("fixed", (80.0, 95.0))}
)

def discover_esx_vsphere_counters_gpu_mem(section: Section) -> DiscoveryResult:
    for name, instances in section.items():
        if name == "gpu.mem.used" :
            for gpu_id, metrics in instances.items():
              yield Service(item=(gpu_id))

def check_esx_vsphere_counters_gpu_mem(
    item: str,
    params: Mapping[str, Any],
    section: Section,
) -> CheckResult:
    memory_metric = {}
    metric_names_list = ("gpu.mem.used","gpu.mem.total")
    for metric_name in metric_names_list :
        data = section.get(metric_name, {}).get(item)
        multivalues, _unit = data[0] if data else (None, None)
        if multivalues is not None:
            value = int(multivalues[0]) * 1000
            memory_metric[metric_name] = value
        else:
          yield Result(state=State.UNKNOWN, summary="Gpu Memory Metric received but no values found")
        
    yield from check_element(
        label="Usage",
        used=memory_metric["gpu.mem.used"],
        total=memory_metric["gpu.mem.total"],
        levels=("perc_used", params.get("levels_upper", (80.0, 90.0))),
        metric_name="mem_used",
    )
    yield Metric("mem_total", memory_metric["gpu.mem.total"])
    

check_plugin_esx_vsphere_gpu_mem = CheckPlugin(
    name="esx_vsphere_counters_gpu_mem",
    sections=["esx_vsphere_counters"],
    service_name="GPU Memory %s",
    discovery_function=discover_esx_vsphere_counters_gpu_mem,
    check_function=check_esx_vsphere_counters_gpu_mem,
    check_default_parameters={"levels_upper": (80.0, 90.0)}# Not intended for check_levels (v2)
)

def check_esx_vsphere_counters_gpu_temperature(
    item: str,
    params: Mapping[str, Any],
    section: Section,
) -> CheckResult:
    temperature_metric = section.get("gpu.temperature", {}).get(item)
    multivalues, _unit = temperature_metric[0] if temperature_metric else (None, None)
    if multivalues is not None:
        temperature = float(multivalues[0])
        yield from check_levels(
            temperature,
            levels_upper=params.get("levels_upper", ("fixed", (80.0, 95.0))),
            metric_name="gpu_temperature",
            render_func=lambda v: "%.1f°C" % v,
            boundaries=(0, 120),
            label="Temperature",
        )
    else:
        yield Result(state=State.UNKNOWN, summary="GPU Temperature metric received but no values found")


def discover_esx_vsphere_counters_gpu_temperature(section: Section) -> DiscoveryResult:
    if debug.enabled():
        print("[plugin esx_vsphere_counters_gpu] ESX GPU Temperature service discovery started")
    for name, instances in section.items():
        if name == "gpu.temperature":
            for gpu_id, metrics in instances.items():
                if debug.enabled():
                    print("[plugin esx_vsphere_counters_gpu_temeprature] ESX GPU Temperature found on PCIE", gpu_id)
                yield Service(item=gpu_id)

check_plugin_esx_vsphere_gpu_temperature = CheckPlugin(
    name="esx_vsphere_counters_gpu_temperature",
    sections=["esx_vsphere_counters"],
    service_name="GPU Temperature %s",
    discovery_function=discover_esx_vsphere_counters_gpu_temperature,
    check_function=check_esx_vsphere_counters_gpu_temperature,
    check_default_parameters={"levels_upper": ("fixed", (80.0, 95.0))}
)

def check_esx_vsphere_counters_gpu_power(
    item: str,
    params: Mapping[str, Any],
    section: Section,
) -> CheckResult:
    power_metric = section.get("gpu.power.used", {}).get(item)
    multivalues, _unit = power_metric[0] if power_metric else (None, None)
    if multivalues is not None:
        power_used = int(multivalues[0])
        yield Metric("gpu_power_used", power_used)
        yield Result(state=State.OK, summary=f"GPU Power Used: {power_used} W")
    else:
        yield Result(state=State.UNKNOWN, summary="GPU Power metric received but no values found")

def discover_esx_vsphere_counters_gpu_power(section: Section) -> DiscoveryResult:
    for name, instances in section.items():
        if name == "gpu.power.used":
            for gpu_id, metrics in instances.items():
                yield Service(item=gpu_id)

check_plugin_esx_vsphere_gpu_power = CheckPlugin(
    name="esx_vsphere_counters_gpu_power",
    sections=["esx_vsphere_counters"],
    service_name="GPU Power %s",
    discovery_function=discover_esx_vsphere_counters_gpu_power,
    check_function=check_esx_vsphere_counters_gpu_power,
    check_default_parameters={}
)
