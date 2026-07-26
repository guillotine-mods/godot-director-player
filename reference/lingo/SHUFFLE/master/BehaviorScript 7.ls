on exitFrame
  global sfl, sfl2, foe, soundspath
  if the locV of sprite 6 < the locV of sprite 11 then
    set the visible of sprite 4 to 0
    set the visible of sprite 11 to 1
  else
    set the visible of sprite 4 to 1
    set the visible of sprite 11 to 0
  end if
  if sprite 6 intersects 4 and ((the locV of sprite 6 - the locV of sprite 4) < 20) then
    if item 3 of sfl = "0" then
      x = the locH of sprite 6 - value(item 1 of sfl)
      y = the locV of sprite 6 - value(item 2 of sfl)
      put "move" into item 3 of sfl
      put x into item 1 of sfl2
      put y into item 2 of sfl2
    else
      put random(30) + 7 into item 1 of sfl2
      y = the locV of sprite 6 - value(item 2 of sfl)
      put y into item 2 of sfl2
      put "move" into item 3 of sfl
    end if
  else
    put the locH of sprite 6 into item 1 of sfl
    put the locV of sprite 6 into item 2 of sfl
  end if
  if sprite 4 intersects 3 and (value(item 2 of sfl2) < 1) then
    put -1 * value(item 2 of sfl2) into item 2 of sfl2
  else
    if sprite 4 intersects 15 and (value(item 2 of sfl2) > -1) then
      if item 2 of sfl2 = "0" then
        put -3 into item 2 of sfl2
      else
        put "-" & value(item 2 of sfl2) into item 2 of sfl2
      end if
    else
      if sprite 4 intersects 10 and ((the locV of sprite 4 - the locV of sprite 10) < 20) and (item 3 of sfl = "move") then
        put "-" & random(30) + 7 into item 1 of sfl2
        put random(14) into item 2 of sfl2
        put "movbak" into item 3 of sfl
      else
        if sprite 4 intersects 7 then
          go("hezscores")
        else
          if sprite 4 intersects 8 then
            go("enescores")
          else
            if (sprite 4 intersects 16 or sprite 4 intersects 17) and (value(item 1 of sfl2) < 1) then
              put -1 * value(item 1 of sfl2) into item 1 of sfl2
            else
              if (sprite 4 intersects 18 or sprite 4 intersects 19) and (value(item 1 of sfl2) > -1) then
                put "-" & value(item 1 of sfl2) into item 1 of sfl2
              else
                if (item 3 of sfl = "move") or (item 3 of sfl = "movbak") then
                  set the locH of sprite 11 to the locH of sprite 11 + value(item 1 of sfl2)
                  set the locV of sprite 11 to the locV of sprite 11 + value(item 2 of sfl2)
                  set the locH of sprite 4 to the locH of sprite 4 + value(item 1 of sfl2)
                  set the locV of sprite 4 to the locV of sprite 4 + value(item 2 of sfl2)
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  if the locH of sprite 4 > 455 then
    if the locV of sprite 4 > the locV of sprite 10 then
      set the locV of sprite 10 to the locV of sprite 10 + value(item 1 of foe)
    else
      set the locV of sprite 10 to the locV of sprite 10 - value(item 1 of foe)
    end if
    if the locH of sprite 4 > the locH of sprite 10 then
      set the locH of sprite 10 to the locH of sprite 10 + value(item 2 of foe)
    else
      set the locH of sprite 10 to the locH of sprite 10 - value(item 2 of foe)
    end if
  end if
  if (the locH of sprite 4 > 640) or (the locH of sprite 4 < 0) or (the locV of sprite 4 > 420) or (the locV of sprite 4 < 210) then
    sound playFile 1, soundspath & "warn.aif"
    go("strtmtch")
  else
    go(marker(0) + 1)
  end if
end
