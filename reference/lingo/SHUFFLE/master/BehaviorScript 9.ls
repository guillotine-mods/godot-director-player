on exitFrame
  global effectspath, sfl, sfl2, foe
  if the locV of sprite 6 < the locV of sprite 11 then
    sprite(4).visible = 0
    sprite(11).visible = 1
  else
    sprite(4).visible = 1
    sprite(11).visible = 0
  end if
  if sprite 6 intersects 4 and ((the locV of sprite 6 - the locV of sprite 4) < 20) then
    if item 3 of sfl = "0" then
      x = the locH of sprite 6 - value(item 1 of sfl)
      y = the locV of sprite 6 - value(item 2 of sfl)
      put "move" into item 3 of sfl
      if not soundBusy(1) then
        sound playFile 1, effectspath & "shfbang2.aif"
      end if
      put x into item 1 of sfl2
      put y into item 2 of sfl2
    else
      put random(30) + 7 into item 1 of sfl2
      y = the locV of sprite 6 - value(item 2 of sfl)
      put y into item 2 of sfl2
      put "move" into item 3 of sfl
      if not soundBusy(1) then
        sound playFile 1, effectspath & "shfbang1.aif"
      end if
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
        if not soundBusy(1) then
          sound playFile 1, effectspath & "shfbang2.aif"
        end if
        put "movbak" into item 3 of sfl
      else
        if sprite 4 intersects 7 then
          sound playFile 3, effectspath & "shfwin.aif"
          go("hezscores")
        else
          if sprite 4 intersects 8 then
            sound playFile 3, effectspath & "shflos.aif"
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
    if the locH of sprite 4 > 655 then
      set the locH of sprite 4 to 197
      set the locV of sprite 4 to 360
      set the locH of sprite 11 to 197
      set the locV of sprite 11 to 360
      put the locH of sprite 4 into item 1 of sfl2
      put the locV of sprite 4 into item 2 of sfl2
      puppetSprite(101, 1)
      set the memberNum of sprite 101 to the number of member "hez"
      put 0 into item 3 of sfl
      puppetSprite(6, 1)
      puppetSprite(4, 1)
      puppetSprite(11, 1)
      sprite(4).visible = 0
      sprite(11).visible = 1
      set the moveableSprite of sprite 6 to 1
      set the constraint of sprite 6 to 2
      set the constraint of sprite 7 to 2
      go(marker(1))
      go("strtmtch")
    end if
  end if
end
