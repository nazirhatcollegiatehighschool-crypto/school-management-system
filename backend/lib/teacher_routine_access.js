function routineSubjectScopeSql({ classAlias = 'c', subjectAlias = 'sub' } = {}) {
  return `EXISTS (
    SELECT 1 FROM routines teacher_routine
    WHERE teacher_routine.teacher_id = ?
      AND teacher_routine.subject_id = ${subjectAlias}.id
      AND (
        EXISTS (
          SELECT 1 FROM routine_sections teacher_routine_section
          WHERE teacher_routine_section.routine_id = teacher_routine.id
            AND teacher_routine_section.class_id = ${classAlias}.id
            AND teacher_routine_section.section = ${classAlias}.section
        )
        OR EXISTS (
          SELECT 1 FROM routine_groups teacher_routine_group
          WHERE teacher_routine_group.routine_id = teacher_routine.id
            AND teacher_routine_group.class_id = ${classAlias}.id
            AND teacher_routine_group.group_name = ${classAlias}.group_name
        )
      )
  )`;
}

module.exports = { routineSubjectScopeSql };
