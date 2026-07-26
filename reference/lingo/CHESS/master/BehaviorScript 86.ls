on exitFrame
  global soundspath, ches2
  if the mouseDown then
    repeat with i = 8 to 15
      puppetSprite(i, 1)
    end repeat
    sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
    ches2 = member(the memberNum of sprite 8).name
    go(marker(1))
  end if
end
