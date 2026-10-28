-- FluentPath V2 starter curriculum, exercises, daily practice, and a sample TOEFL simulation.
begin;
insert into public.daily_quests(title,description,target_count,xp_reward,quest_type) values
 ('One good question','Answer one exercise correctly today.',1,20,'complete_exercises'),
 ('Practice three times','Answer three exercises correctly today.',3,35,'complete_exercises'),
 ('Earn a little momentum','Earn 40 XP through lessons and practice today.',40,25,'earn_xp')
on conflict(title) do nothing;

insert into public.achievements(slug,title,description,icon,xp_reward,criteria_type,criteria_threshold) values
 ('first-lesson','First lesson','Complete your first learning lesson.','01',50,'lessons_completed',1),
 ('first-toefl','Practice simulation','Finish your first TOEFL practice simulation.','T',50,'toefl_score',1),
 ('seven-day-streak','A week of practice','Study on seven consecutive days.','7',100,'streak_days',7),
 ('perfect-practice','Careful work','Earn a perfect score in a lesson.','✓',40,'perfect_score',1)
on conflict(slug) do nothing;

insert into public.lessons(title,slug,description,cefr_level,category,order_index,xp_reward,estimated_minutes,is_published) values
 ('The verb to be','a1-verb-to-be','Use am, is, and are to introduce people and describe familiar things.','A1','grammar',1,20,8,false),
 ('At the neighbourhood café','a1-cafe-vocabulary','Practise useful words for ordering a drink and asking a simple question.','A1','vocabulary',2,20,8,false),
 ('A note about the new flat','a2-reading-a-note','Read a short message and identify details about a recent move.','A2','reading',1,25,10,false),
 ('Platform two','a2-listening-at-the-station','Listen for a departure time and platform announcement.','A2','listening',2,25,9,false),
 ('A week in progress','b1-present-perfect','Choose between the present perfect and past simple in context.','B1','grammar',1,30,12,false),
 ('Describe a learning habit','b1-speaking-routine','Give a short spoken or written answer about a habit that helps you learn.','B1','speaking',2,30,10,false),
 ('Collocations at work','b2-vocabulary-collocations','Choose natural word partnerships used in everyday professional English.','B2','vocabulary',1,35,12,false),
 ('A clear request','b2-writing-a-request','Write a concise, polite request with the context the reader needs.','B2','writing',2,35,12,false),
 ('Careful claims','c1-reading-hedging','Notice how writers signal the strength and limits of evidence.','C1','reading',1,40,14,false),
 ('Cause and correlation','c1-listening-correlation','Listen for the distinction between a pattern and its cause.','C1','listening',2,40,14,false),
 ('Inversion for emphasis','c2-inversion-emphasis','Use negative adverbials to add emphasis in formal English.','C2','grammar',1,45,14,false),
 ('A balanced recommendation','c2-speaking-recommendation','Present a nuanced recommendation and acknowledge a trade-off.','C2','speaking',2,45,15,false)
on conflict(slug) do update set title=excluded.title,description=excluded.description,cefr_level=excluded.cefr_level,category=excluded.category,order_index=excluded.order_index,xp_reward=excluded.xp_reward,estimated_minutes=excluded.estimated_minutes,is_published=false;

insert into public.lesson_sections(lesson_id,title,content,section_type,order_index)
select l.id,s.title,s.content,'concept',1 from (values
 ('a1-verb-to-be','A small verb with a big job','Use **am** with I, **is** with he, she, or it, and **are** with you, we, or they. The verb connects a person or thing to a description: *I am ready. They are neighbours.*'),
 ('a1-cafe-vocabulary','Useful café language','A **menu** lists food and drinks. You can **order** a tea, ask for the **bill**, or say **for here** and **to go**. A polite request often begins with *Could I have…?*'),
 ('a2-reading-a-note','Read for the details','Read the message once for its main point. Read it again to find names, dates, and reasons. Small time words such as *until* and *after* change the meaning of a plan.'),
 ('a2-listening-at-the-station','Listen for the change','Station announcements often repeat the destination, time, and platform. Listen once for the situation, then listen again for the details you need.'),
 ('b1-present-perfect','Experience and finished time','Use the **present perfect** for an experience connected to now: *I have visited twice.* Use the **past simple** with a finished time: *I visited last spring.*'),
 ('b1-speaking-routine','Make your answer concrete','A clear short answer names the habit, says when you do it, and gives one reason it helps. A small example is easier to follow than a broad claim.'),
 ('b2-vocabulary-collocations','Words that travel together','Natural English often pairs words in familiar ways. We **meet a deadline**, **raise a concern**, and **reach an agreement**. Learning the pair helps your sentence sound precise.'),
 ('b2-writing-a-request','Give the reader enough context','A useful request explains what you need, why you need it, and when it would help. Keep the tone polite and make the action clear.'),
 ('c1-reading-hedging','Match the strength of the claim','Academic writers use words such as **may**, **suggests**, and **is associated with** when evidence has limits. These phrases keep a claim proportional to what the study shows.'),
 ('c1-listening-correlation','Separate pattern from cause','Two measures can change together without one causing the other. Listen for the evidence offered and for any limits the speaker names.'),
 ('c2-inversion-emphasis','Formal inversion','After a negative adverbial such as **Rarely** or **Not only**, formal English places the auxiliary before the subject: *Rarely have we seen…* The meaning stays the same, but the emphasis changes.'),
 ('c2-speaking-recommendation','Show your reasoning','A nuanced recommendation states a position, recognises a practical trade-off, and explains why the choice still makes sense in the situation.')
) as s(slug,title,content) join public.lessons l on l.slug=s.slug
on conflict(lesson_id,order_index) do update set title=excluded.title,content=excluded.content;

insert into public.exercises(lesson_id,exercise_type,prompt,passage,rubric,points,order_index)
select l.id,s.kind::public.exercise_type,s.prompt,s.passage,s.rubric,10,1 from (values
 ('a1-verb-to-be','multiple_choice','Choose the correct verb: “My friends ___ ready for class.”',null,null),
 ('a1-cafe-vocabulary','multiple_choice','Which phrase politely asks for a drink?',null,null),
 ('a2-reading-a-note','reading_comprehension','Mina writes: “I moved into the blue house on Friday. The kitchen is small, but the garden gets morning sun. Come by after six on Tuesday.” What time does Mina invite her friend to visit?',E'Hi Jo,\nI moved into the blue house on Friday. The kitchen is small, but the garden gets morning sun. Come by after six on Tuesday.\nMina',null),
 ('a2-listening-at-the-station','listening','Listen to the announcement. Which platform should passengers use?','The 10:20 train to Brighton is delayed by five minutes. It will now leave from platform four. Please keep your ticket ready.',null),
 ('b1-present-perfect','multiple_choice','Complete the sentence: “I ___ that film twice, so I know the ending.”',null,null),
 ('b1-speaking-routine','short_response','Speak or write about one habit that helps you learn. When do you do it, and why does it help?','', 'Name the habit, give a specific example of when you use it, and explain how it helps you learn.'),
 ('b2-vocabulary-collocations','multiple_choice','Choose the natural collocation: “We need to ___ a decision before Friday.”',null,null),
 ('b2-writing-a-request','short_response','Write a polite message asking a colleague to review a draft before Thursday. Include why you need their help.','', 'Check that your request is clear, polite, and includes a reason and a useful deadline.'),
 ('c1-reading-hedging','reading_comprehension','The report says the new schedule “may be associated with fewer missed appointments,” while noting that the sample was small. Which claim is best supported?','The report says the new schedule “may be associated with fewer missed appointments,” while noting that the sample was small.',null),
 ('c1-listening-correlation','listening','Listen to the talk. What does the speaker say the data can show?','In our survey, students who slept longer also reported better focus. The pattern is consistent across two groups, but the survey cannot show that sleep alone caused the change. Other factors may be involved.',null),
 ('c2-inversion-emphasis','multiple_choice','Choose the formal sentence that means “We had rarely seen such a clear result.”',null,null),
 ('c2-speaking-recommendation','short_response','Recommend one change that would improve a team meeting. Acknowledge one drawback and explain why your recommendation is still useful.','', 'State a recommendation, recognise a genuine trade-off, and connect your reasoning to the team’s needs.')
) as s(slug,kind,prompt,passage,rubric) join public.lessons l on l.slug=s.slug
on conflict(lesson_id,order_index) do update set exercise_type=excluded.exercise_type,prompt=excluded.prompt,passage=excluded.passage,rubric=excluded.rubric;

insert into public.exercise_options(exercise_id,option_text,is_correct,explanation,order_index)
select e.id,o.label,o.is_correct,o.explanation,o.position
from (values
 ('a1-verb-to-be','is',false,'“Is” goes with he, she, or it.',1),('a1-verb-to-be','are',true,'“Friends” is plural, so it takes “are”.',2),('a1-verb-to-be','am',false,'“Am” goes with “I”.',3),
 ('a1-cafe-vocabulary','Give a tea.',false,'This is understandable, but it is not a polite request.',1),('a1-cafe-vocabulary','Could I have a tea, please?',true,'“Could I have…?” is a polite way to order.',2),('a1-cafe-vocabulary','Where is my tea?',false,'This asks where the drink is, rather than ordering it.',3),
 ('a2-reading-a-note','Before six on Monday.',false,'The note says after six on Tuesday.',1),('a2-reading-a-note','After six on Tuesday.',true,'Mina says, “Come by after six on Tuesday.”',2),('a2-reading-a-note','On Friday morning.',false,'Friday is when Mina moved, not the visit time.',3),
 ('a2-listening-at-the-station','Platform two.',false,'The announcement says platform four.',1),('a2-listening-at-the-station','Platform four.',true,'The train now leaves from platform four.',2),('a2-listening-at-the-station','Platform five.',false,'The announcement does not say platform five.',3),
 ('b1-present-perfect','have seen',true,'“Twice” describes experience up to now, so use the present perfect.',1),('b1-present-perfect','saw yesterday',false,'A finished time such as “yesterday” would use past simple.',2),('b1-present-perfect','am seeing',false,'This describes an action happening now, not past experience.',3),
 ('b2-vocabulary-collocations','do a decision',false,'“Do” does not naturally pair with “decision”.',1),('b2-vocabulary-collocations','make a decision',true,'“Make a decision” is the natural collocation.',2),('b2-vocabulary-collocations','take a decisioning',false,'“Decisioning” is not the intended noun here.',3),
 ('c1-reading-hedging','The schedule may be linked with fewer missed appointments.',true,'This preserves “may be associated” and the limited evidence.',1),('c1-reading-hedging','The schedule always prevents missed appointments.',false,'The report does not establish certainty or prevention.',2),('c1-reading-hedging','The schedule has no relationship to appointments.',false,'That claim is stronger than the report supports.',3),
 ('c1-listening-correlation','The survey shows sleep alone caused better focus.',false,'The speaker says the survey cannot establish a cause.',1),('c1-listening-correlation','Longer sleep and better focus appeared together in the survey.',true,'The survey found an association, while naming other possible factors.',2),('c1-listening-correlation','The survey proves that every student needs the same sleep schedule.',false,'The speaker describes a pattern, not a universal rule.',3),
 ('c2-inversion-emphasis','Rarely we had seen such a clear result.',false,'The auxiliary must come before the subject after “Rarely”.',1),('c2-inversion-emphasis','Rarely had we seen such a clear result.',true,'The negative adverbial triggers formal subject-auxiliary inversion.',2),('c2-inversion-emphasis','Rarely seen we such a clear result.',false,'The auxiliary is missing from the sentence.',3)
) as o(slug,label,is_correct,explanation,position)
join public.lessons l on l.slug=o.slug
join public.exercises e on e.lesson_id=l.id and e.order_index=1
on conflict(exercise_id,order_index) do update set option_text=excluded.option_text,is_correct=excluded.is_correct,explanation=excluded.explanation;

insert into public.exam_sets(title,description,cefr_level,duration_seconds,is_published)
values('TOEFL skills practice','A short practice simulation covering comprehension, language use, and a brief response.','B1',1200,true)
on conflict do nothing;
insert into public.exam_questions(exam_id,category,prompt,passage,rubric,is_objective,points,order_index)
select x.id,q.category::public.skill_category,q.prompt,q.passage,q.rubric,q.objective,1,q.position from public.exam_sets x cross join (values
 ('reading','Read the sentence: “The museum closes at five, except on Thursdays.” When does it close at five?','The museum closes at five, except on Thursdays.',null,true,1),
 ('listening','Listen to the message. When will the speaker call back?','Hi, this is Lena. I am in a meeting until half past two, so I will call you as soon as I am free.','',true,2),
 ('grammar','Choose the correct sentence.','',null,true,3),
 ('vocabulary','Choose the word closest in meaning to “brief”.','',null,true,4),
 ('writing','Write a short email asking for information about a course. Include one specific question and a polite closing.','', 'Check that your purpose and question are clear and the tone is appropriate.',false,5),
 ('speaking','Give a short recommendation for a quiet place to study. Explain why it suits the person.','', 'Name a place, give a relevant reason, and connect it to the listener’s needs.',false,6)
) as q(category,prompt,passage,rubric,objective,position)
where x.title='TOEFL skills practice'
on conflict(exam_id,order_index) do update set prompt=excluded.prompt,passage=excluded.passage,rubric=excluded.rubric,is_objective=excluded.is_objective;
insert into public.exam_question_options(question_id,option_text,is_correct,explanation,order_index)
select q.id,o.label,o.correct,o.note,o.choice_order from public.exam_questions q join public.exam_sets x on x.id=q.exam_id
join (values
 (1,'At four o’clock.',false,'The message says the caller is in a meeting until half past two.',1),(1,'After half past two.',true,'Lena will call when the meeting ends.',2),(1,'Before two o’clock.',false,'The call will be after the meeting.',3),
 (2,'will call',true,'The future form fits this promise.',1),(2,'called',false,'The sentence describes a future action.',2),(2,'has called',false,'The call has not happened yet.',3),
 (3,'The instructions were clear and easy to follow.',true,'This sentence is grammatical and natural.',1),(3,'The instructions was clear and easy to follow.',false,'The plural subject takes “were”.',2),(3,'The instructions are clearly followed easy.',false,'The word order and form are incorrect.',3),
 (4,'short',true,'“Brief” means short in time or length.',1),(4,'distant',false,'“Distant” describes space or relationship.',2),(4,'careless',false,'“Careless” describes a lack of attention.',3)
) as o(position,label,correct,note,choice_order) on q.order_index=o.position
where x.title='TOEFL skills practice'
on conflict(question_id,order_index) do update set option_text=excluded.option_text,is_correct=excluded.is_correct,explanation=excluded.explanation;

update public.lessons set is_published=true where slug in (
 'a1-verb-to-be','a1-cafe-vocabulary','a2-reading-a-note','a2-listening-at-the-station',
 'b1-present-perfect','b1-speaking-routine','b2-vocabulary-collocations','b2-writing-a-request',
 'c1-reading-hedging','c1-listening-correlation','c2-inversion-emphasis','c2-speaking-recommendation'
);
commit;

