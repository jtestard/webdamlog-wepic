#collection ext persistent person_example@local(_id*,name*); #Custom content
#collection ext persistent friend_example@local(_id1*,_id2*);
#fact picture@local(sigmod,Jules,12345,"http://www.sigmod.org/about-sigmod/sigmod-logo/archive/800x256/sigmod.gif");
#fact picture@local(sigmod,Julia,12346,"http://www.sigmod.org/about-sigmod/sigmod-logo/archive/800x256/sigmod.gif");
#fact picture@local(me,Jules,12349,"http://www.cs.mcgill.ca/~jtesta/images/profile.png");
#fact picture@local(me,Julia,12350,"http://www.cs.columbia.edu/~jds1/pic_7.jpg");
#fact picture@local(me,Julia,12351,"http://www.cs.tau.ac.il/workshop/modas/julia.png");
#fact rating@local(12347,5,Jules);
#fact rating@local(12348,5,Julia);
#fact person_example@local(12345,oscar);
#fact person_example@local(12346,hugo);
#fact person_example@local(12347,kendrick);
#fact friend_example@local(12345,12346);
#fact friend_example@local(12346,12347);
#fact picturelocation@local(12345,"New York");
#fact picturelocation@local(12346,"New York");
#fact picturelocation@local(12347,"New York");
#fact picturelocation@local(12348,"Paris, France");
#fact picturelocation@local(12349,"McGill University");
#fact contact@local(Jules, "127.0.0.1", 4100, false, "jules.testard@mail.mcgill.ca");
#fact contact@local(Julia, "127.0.0.1", 4150, false, "stoyanovich@drexel.edu");
#rule person_example@local($id,$name) :- friend_example@local($id,$name);