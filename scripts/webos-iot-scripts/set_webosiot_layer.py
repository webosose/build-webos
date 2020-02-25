# Copyright (c) 2020 LG Electronics, Inc.

import re
import os
import sys

version = "1.0.0"

def make_webosiot_layers_as_rule(path):
    sys.path.insert(0,path)
    if not os.path.isfile(os.path.join(path,'weboslayers.py')):
        raise Exception("Error: Configuration file %s does not exist!" % os.path.join(path,'weboslayers.py'))

    from webosiot_rule import webosiot_layer_rules
    from weboslayers import webos_layers

    maxpriority = webos_layers[-1][1]

    for rule in webosiot_layer_rules:
        action = rule[0]
        if action == 'remove':
            del webos_layers[layer_index(webos_layers, rule[1])]
        elif action == 'insert':
            webos_layers.insert(layer_index(webos_layers, rule[1]) + 1, rule[2])
        elif action == 'append':
            appendlayer = list(rule[1])
            appendlayer[1] = maxpriority + 1
            webos_layers.append(tuple(appendlayer))
            maxpriority += 1

    return webos_layers

def layer_index(webos_layers, layername):
    weboslayerlist = [l[0] for l in webos_layers]
    return weboslayerlist.index(layername)

def replace_str_in_file(fname, pattern, dststr):
    with open(fname, "r") as f:
        content = f.read()

    content = re.sub(pattern, dststr, content, flags=re.DOTALL)

    with open(fname, 'w+') as f:
        f.write(content)

def list_to_linebreak_str(layerlist):
    layerstr = "[\n"
    for layer in layerlist:
        layerstr = layerstr + str(layer) + ",\n";
    layerstr = layerstr + "]"
    return layerstr;

if __name__ == '__main__':
    rootdir = os.getcwd()

    # modify webos_layers list of weboslayers.py as webosiot_rule.py
    webosiotlayers = make_webosiot_layers_as_rule(rootdir)

    # replace webos_layer variable in weboslayers.py with webos_layer list for webosiot
    replace_str_in_file('weboslayers.py', '\nwebos_layers = \[.*\]', '\nwebos_layers = ' + list_to_linebreak_str(webosiotlayers))
