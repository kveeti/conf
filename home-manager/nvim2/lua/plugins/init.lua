return {
  main = function() 
    require('plugins.telescope').main()
    require('plugins.languages').main()
    require('plugins.autocomplete').main()
    require('plugins.auto').main()
  end
}
