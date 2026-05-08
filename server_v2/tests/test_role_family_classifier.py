from app.services.persona_service import classify_role_family


def test_teacher_is_educator():
    assert classify_role_family("teacher") == "educator"


def test_student_is_learner():
    assert classify_role_family("student") == "learner"


def test_professional_is_professional():
    assert classify_role_family("professional") == "professional"


def test_manager_is_professional():
    assert classify_role_family("manager") == "professional"


def test_freelancer_is_professional():
    assert classify_role_family("freelancer") == "professional"


def test_homemaker_is_casual():
    assert classify_role_family("homemaker") == "casual"


def test_other_is_default():
    assert classify_role_family("other") == "default"


def test_unknown_string_is_default():
    assert classify_role_family("astronaut") == "default"
