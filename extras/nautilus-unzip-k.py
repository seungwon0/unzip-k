# nautilus-unzip-k.py - Nautilus Extension for UnZip-K
#
# It adds 'Extract Here (UnZip-K)' menu in Nautilus.
#
# In Ubuntu, you can install this program using the following commands:
# % sudo apt-get install python-nautilus
# % sudo cp nautilus-unzip-k.py /usr/lib/nautilus/extensions-2.0/python
# % nautilus -q
#
# You can learn more about UnZip-K at the following link:
# https://github.com/seungwon0/unzip-k
#
# Seungwon Jeong <seungwon0@gmail.com>
#
# Copyright (C) 2011 by Seungwon Jeong

import nautilus

import os

import urllib

import re

class Unzip_k(nautilus.MenuProvider):
    def __init__(self):
        pass

    def menu_activate_cb(self, menu, files):
        # Strip leading file://
        path = urllib.unquote(files[0].get_parent_uri()[7:])
        os.chdir(path)

        pattern = re.compile(r'\.zip$', flags=re.IGNORECASE);

        for file in files:
            file_name = file.get_name()
            dir_name = pattern.sub('', file_name)
            if dir_name == file_name:
                dir_name += '.dir'
            os.system("unzip-k '%s' -d '%s' &" % (file_name, dir_name))

    def get_file_items(self, window, files):
        if len(files) == 0:
            return

        for file in files:
            if file.get_mime_type() != 'application/zip':
                return

        item = nautilus.MenuItem('Unzip_k::Extract_Here',
                                 'Extract Here (UnZip-K)',
                                 'Extract Here (UnZip-K)')
        item.connect('activate', self.menu_activate_cb, files)

        return [item]
