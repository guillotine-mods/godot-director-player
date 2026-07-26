on whatodoeveryframe2
  global whatodo, egozh, egozv, upordown, stopornot, nextroomdata, resizepip, hope, newsyz, syz, ifmovie
  if whatodo = "walktime" then
    set the visible of sprite 31 to 0
    if member(the memberNum of sprite 30).name contains "subleft" then
      if (the locH of sprite 30 - 10) < egozh then
        put "ok" into item 1 of stopornot
      else
        set the locH of sprite 30 to the locH of sprite 30 - 16
      end if
      put value(item 3 of stopornot) + 1 into item 3 of stopornot
      if value(item 3 of stopornot) = 7 then
        put 1 into item 3 of stopornot
      end if
      x = value(item 3 of stopornot)
      if (the locV of sprite 30 - 10) < egozv then
        set the memberNum of sprite 30 to the number of member ("subleft" & x) of castLib 1
      else
        set the memberNum of sprite 30 to the number of member ("subleftup" & x) of castLib 1
      end if
    else
      if member(the memberNum of sprite 30).name contains "subright" then
        if (the locH of sprite 30 + 10) > egozh then
          put "ok" into item 1 of stopornot
        else
          set the locH of sprite 30 to the locH of sprite 30 + 16
        end if
        put value(item 3 of stopornot) + 1 into item 3 of stopornot
        if value(item 3 of stopornot) = 7 then
          put 1 into item 3 of stopornot
        end if
        x = value(item 3 of stopornot)
        if (the locV of sprite 30 - 10) < egozv then
          set the memberNum of sprite 30 to the number of member ("subright" & x) of castLib 1
        else
          set the memberNum of sprite 30 to the number of member ("subrightup" & x) of castLib 1
        end if
      end if
    end if
    if hope <> 0 then
      set the locV of sprite 30 to the locV of sprite 30 + hope
      hope = 0
    end if
    if upordown = "up" then
      if (the locV of sprite 30 - 10) < egozv then
        put "ok" into item 2 of stopornot
      else
        if item 1 of stopornot = "ok" then
          set the locV of sprite 30 to the locV of sprite 30 - 10
        else
          set the locV of sprite 30 to the locV of sprite 30 - 10
        end if
      end if
    else
      if upordown = "down" then
        if (the locV of sprite 30 + 10) > egozv then
          put "ok" into item 2 of stopornot
        else
          if item 1 of stopornot = "ok" then
            set the locV of sprite 30 to the locV of sprite 30 + 10
          else
            set the locV of sprite 30 to the locV of sprite 30 + 10
          end if
        end if
      end if
    end if
    updateStage()
    if (item 1 of stopornot = "ok") and (item 2 of stopornot = "ok") then
      whatodo = "stand"
      upordown = "stand"
    end if
  else
    if whatodo = "stand" then
      if member(the memberNum of sprite 30).name contains "subright" then
        set the memberNum of sprite 30 to the number of member "substandright" of castLib 1
        set the visible of sprite 31 to 1
        set the locH of sprite 31 to the locH of sprite 30
        set the locV of sprite 31 to the locV of sprite 30 - 250
      else
        if member(the memberNum of sprite 30).name contains "subleft" then
          set the visible of sprite 31 to 1
          set the locH of sprite 31 to the locH of sprite 30
          set the locV of sprite 31 to the locV of sprite 30 - 250
          set the memberNum of sprite 30 to the number of member "substandleft" of castLib 1
        end if
      end if
      if nextroomdata <> "000" then
        if value(item 2 of nextroomdata) > 300 then
          set the memberNum of sprite 30 to the number of member "substandleft"
        else
          set the memberNum of sprite 30 to the number of member "substandright"
        end if
        egozh = value(item 2 of nextroomdata)
        egozv = value(item 3 of nextroomdata)
        if item 1 of ifmovie = "1" then
          set the visible of sprite 30 to 0
          put "0" into item 1 of ifmovie
          go(item 2 of ifmovie)
        else
          go(item 1 of nextroomdata)
          nextroomdata = "000"
        end if
      end if
    end if
  end if
end
