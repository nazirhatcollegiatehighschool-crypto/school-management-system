INSERT INTO time_slots (slot_order, label, start_time, end_time, is_break) VALUES
(1,'ASSEMBLY','10:00:00','10:15:00', TRUE),
(2,'CLASS_1','10:15:00','11:05:00', FALSE),
(3,'CLASS_2','11:05:00','11:50:00', FALSE),
(4,'CLASS_3','11:50:00','12:35:00', FALSE),
(5,'CLASS_4','12:35:00','13:15:00', FALSE),
(6,'LEISURE','13:15:00','14:00:00', TRUE),
(7,'CLASS_5','14:00:00','14:40:00', FALSE),
(8,'CLASS_6','14:40:00','15:20:00', FALSE),
(9,'CLASS_7','15:20:00','16:00:00', FALSE) 
ON CONFLICT (slot_order) DO NOTHING;
