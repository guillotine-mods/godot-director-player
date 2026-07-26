on enterFrame
  global afganicnt
  updateStage()
  if the soundLevel = 1 then
    set the locH of sprite 31 to the locH of sprite 24
  else
    if the soundLevel = 2 then
      set the locH of sprite 31 to the locH of sprite 25
    else
      if the soundLevel = 3 then
        set the locH of sprite 31 to the locH of sprite 26
      else
        if the soundLevel = 4 then
          set the locH of sprite 31 to the locH of sprite 27
        else
          if the soundLevel = 5 then
            set the locH of sprite 31 to the locH of sprite 28
          else
            if the soundLevel = 6 then
              set the locH of sprite 31 to the locH of sprite 29
            else
              if the soundLevel = 7 then
                set the locH of sprite 31 to the locH of sprite 30
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  set the cursor of sprite 3 to [1]
  zxc = 10
  repeat with i = 1 to 10
    if line i of field "plane" of castLib 2 = "empty" then
      zxc = zxc - 1
    end if
  end repeat
  if zxc < 10 then
    put "0" & zxc into field "planeitems"
  else
    put 10 into field "planeitems"
  end if
  afganicnt = value(afganicnt)
  put integer(afganicnt) into field "afganitems"
  zxc = 0
  repeat with i = 1 to the number of items in field "jokefield"
    if item i of field "jokefield" <> "1" then
      zxc = zxc + 1
    end if
  end repeat
  put zxc into field "jokesitems"
end
