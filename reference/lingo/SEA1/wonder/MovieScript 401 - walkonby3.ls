on walkonby3
  global whatodo, egozh, egozv, upordown, stopornot, resizepip, syz, hope
  hope = 0
  if (the locH of sprite 30 - 10) > egozh then
    set the memberNum of sprite 30 to the number of member ("walkleft" & "1") of castLib 1
    whatodo = "walktime"
    put "notok" into item 1 of stopornot
  else
    if (the locH of sprite 30 + 10) < egozh then
      set the memberNum of sprite 30 to the number of member ("walkright" & "1") of castLib 1
      whatodo = "walktime"
      put "notok" into item 1 of stopornot
    end if
  end if
  if (egozv + 10) > the locV of sprite 30 then
    upordown = "down"
    put "notok" into item 2 of stopornot
  else
    if (egozv - 10) < the locV of sprite 30 then
      upordown = "up"
      put "notok" into item 2 of stopornot
    end if
  end if
end
