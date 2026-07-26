on exitFrame
  whatodoeveryframe()
  if the visible of sprite 9 = 1 then
    if the locH of sprite 30 < 171 then
      set the memberNum of sprite 9 to the number of member "monkleft"
    else
      if the locH of sprite 30 < 387 then
        set the memberNum of sprite 9 to the number of member "monkmiddle"
      else
        set the memberNum of sprite 9 to the number of member "monkright"
      end if
    end if
  end if
end
