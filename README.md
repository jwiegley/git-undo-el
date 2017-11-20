# git-undo

When `M-x git-undo` is called on a region, it will first:

 1. Replace the region, if it has been modified but not saved, with the
    current working tree version.

 2. Replace the region, if it has been modified and saved, with the current
    HEAD version.
    
 3. Successively walk back through all the versions of that region found in
    the Git history.
    
Note that if this command is run twice, it begins the walkthrough over again,
since there's no easy way of knowing at which point in history you were before
you repeated the command. Perhaps this could be added by searching through the
Git history for matching contents.
