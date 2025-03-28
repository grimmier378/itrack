# itrack

## Simple Item Tracker using Actors

Add items to the list and it will track qty on the character and in their bank.
If you have multiple characters running this on the same machine it will relay the information over actors.

You can right click to remove an item from the list.

The List is resizable by grabbing the right border
The details table on the right has resizable columns so you can scale the window as you please.

All items in the list are saved for future loading.

Searches are not case sensative. so `Iron Ration` is the same as `iron ration`.
Searches use partial names. so you can search for `corroded plate` and find all of the pieces.

Removing or adding items on one character will update the other characters as well.

Item counts update every 3 seconds.
