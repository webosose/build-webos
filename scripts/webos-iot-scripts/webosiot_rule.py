# Copyright (c) 2020 LG Electronics, Inc.

# list of rule to add or remove layer to weboslayers.py of webosose for meta-webos-iot
# set_webosiot_layer.py expects the rules to be defined in this file as a list of Python data tuples:
#
# (<action> := 'append'|'remove'|'insert', <attribute of 'append'> | <attribute of 'remove'> | <attributes of 'insert'>)
#
# <attribute of 'append'> := <tuple of layer to append>
# · priority of appended layer is assigned automatically to bigger value of last layer
# <attribute of 'remove'> := <layer-name in weboslayers.py of webosose>
# <attribute of 'insert'> := <layer-name in weboslayers.py of webosose> "," <tuple of layer to insert>
#
# Examples of rule
# 1. remove 'meta-updater' layer from weboslayers.py of webosose
# ('remove', 'meta-updater')
#
# 2. append 'meta-webos-iot' layer to weboslayers.py of webosose
# ('append', ('meta-webos-iot', 'auto', 'git://github.com/webosose/meta-webos-iot.git', 'branch=webos-headless', 'meta-webos-iot')),
#
# 3. insert 'meta-webos-iot' layer after 'meta-webos' layer of weboslayers.py of webosose
# ('insert', 'meta-webos', ('meta-webos-iot', 41, 'git://github.com/webosose/meta-webos-iot.git', 'branch=webos-headless', 'meta-webos-iot')),

webosiot_layer_rules = [
('append', ('meta-webos-iot', 'auto', 'git://github.com/webosose/meta-webosose.git', '', '')),
]
