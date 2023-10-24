#!/usr/bin/env python3
import sys

import pcbnew
def get_version(pcb):
    board = pcbnew.LoadBoard(pcb)
    title = board.GetTitleBlock()
    version = title.GetRevision()
    return version


if __name__ == "__main__":
    version = get_version(sys.argv[1])
    print(version)
