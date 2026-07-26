on exitFrame
  global soundspath, globalnight
  sound playFile 1, soundspath & "pfhair.aif"
  set the visible of sprite 15 to 0
  put "done" into item 3 of globalnight
  play done
end
