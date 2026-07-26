on whatodoeveryframe
  global whatodo, egozh, egozv, upordown, stopornot, nextroomdata, resizepip, hope, newsyz, syz, ifmovie
  if whatodo = "walktime" then
    if member(the memberNum of sprite 30).name contains "walkleft" then
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
        set the memberNum of sprite 30 to the number of member ("walkleft" & syz & x) of castLib 1
      else
        set the memberNum of sprite 30 to the number of member ("walkleftup" & syz & x) of castLib 1
      end if
    else
      if member(the memberNum of sprite 30).name contains "walkright" then
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
          set the memberNum of sprite 30 to the number of member ("walkright" & syz & x) of castLib 1
        else
          set the memberNum of sprite 30 to the number of member ("walkrightup" & syz & x) of castLib 1
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
        resizepip = resizepip + 1
        if resizepip > 2 then
          resizepip = 0
          syz = syz - 1
          hope = -15
          if syz < 4 then
            syz = 4
          end if
        end if
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
          resizepip = resizepip + 1
          if resizepip > 2 then
            resizepip = 0
            syz = syz + 1
            hope = 13
            updateStage()
            if syz > 9 then
              syz = 9
            end if
          end if
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
      if member(the memberNum of sprite 30).name contains "walkright" then
        set the memberNum of sprite 30 to the number of member ("standright" & syz) of castLib 1
      else
        if member(the memberNum of sprite 30).name contains "walkleft" then
          set the memberNum of sprite 30 to the number of member ("standleft" & syz) of castLib 1
        end if
      end if
      if nextroomdata <> "000" then
        syz = newsyz
        if value(item 2 of nextroomdata) > 300 then
          set the memberNum of sprite 30 to the number of member ("standleft" & newsyz)
        else
          set the memberNum of sprite 30 to the number of member ("standright" & newsyz)
        end if
        egozh = value(item 2 of nextroomdata)
        egozv = value(item 3 of nextroomdata)
        if item 1 of ifmovie = "1" then
          put "0" into item 1 of ifmovie
        else
          go(item 1 of nextroomdata)
          nextroomdata = "000"
        end if
      end if
    end if
  end if
end
