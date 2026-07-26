on exitFrame
  global soundspath, ches1
  if the mouseDown then
    sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
    repeat with i = 8 to 15
      puppetSprite(i, 1)
    end repeat
    go(marker(1))
    ches1 = member(the memberNum of sprite 8).name
  else
    go(marker(0))
  end if
end
