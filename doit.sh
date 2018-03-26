perl htmldiff.pl old.html new.html >diff.html
diff old.html new.html
tidy -e old.html
tidy -e new.html
tidy -e diff.html
cat old.html
cat new.html
cat diff.html

perl htmldiff.pl old.html new2.html >diff2.html
diff old.html new2.html
diff new.html new2.html
tidy -e new2.html
tidy -e diff2.html
cat new2.html
cat diff2.html

echo END
