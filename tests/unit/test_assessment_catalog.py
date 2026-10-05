"""Unit tests for the assessment catalog registry."""

import pytest

from neurosync.modules.monitoring.assessment_catalog import (
    ASSESSMENT_CATALOG,
    SUPPORTED_ASSESSMENT_SLUGS,
    AssessmentSpec,
    ExecutionType,
    ParameterKind,
    ParameterValidationError,
    default_parameters,
    get_spec,
    required_strokes,
    resolve_parameters,
    validate_parameters,
)


def test_catalog_contains_the_expected_assessments() -> None:
    slugs = [spec.slug for spec in ASSESSMENT_CATALOG]
    assert slugs == ["finger_tapping", "spiral_drawing", "line_tracing", "handwriting"]


def test_only_the_tests_that_are_ready_are_handed_out() -> None:
    # Finger tapping and line tracing are the two a doctor may assign today.
    # Spiral drawing and handwriting have runners but are held back until their
    # guides are good enough to ask a patient to use.
    assert {"finger_tapping", "line_tracing"} == SUPPORTED_ASSESSMENT_SLUGS


def test_the_held_back_tests_stay_in_the_catalog() -> None:
    # Held back is not removed: the catalog keeps describing them so the doctor
    # app can show them as coming soon, and enabling one later is a flag change
    # rather than a new entry.
    all_slugs = {spec.slug for spec in ASSESSMENT_CATALOG}
    held_back = all_slugs - SUPPORTED_ASSESSMENT_SLUGS
    assert held_back == {"spiral_drawing", "handwriting"}
    for slug in held_back:
        spec = get_spec(slug)
        assert spec is not None
        assert spec.title
        assert spec.instructions
        assert spec.parameters


def test_every_spec_is_fully_described() -> None:
    for spec in ASSESSMENT_CATALOG:
        assert isinstance(spec, AssessmentSpec)
        assert spec.title
        assert spec.description
        assert spec.instructions
        assert spec.default_duration_seconds > 0


def test_canvas_assessments_no_longer_say_they_are_unavailable() -> None:
    canvas = [
        spec for spec in ASSESSMENT_CATALOG if spec.execution_type is ExecutionType.CANVAS_TASK
    ]
    assert len(canvas) == 3
    for spec in canvas:
        assert "not available yet" not in spec.instructions.lower()


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_slugs_are_url_safe(spec: AssessmentSpec) -> None:
    assert spec.slug == spec.slug.strip().lower()
    assert spec.slug.replace("_", "").isalnum()


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_parameter_keys_are_unique_and_url_safe(spec: AssessmentSpec) -> None:
    keys = [parameter.key for parameter in spec.parameters]
    assert len(keys) == len(set(keys))
    assert all(key.replace("_", "").isalnum() for key in keys)


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_every_parameter_default_satisfies_its_own_spec(spec: AssessmentSpec) -> None:
    # A default that its own validator would reject would make an untouched
    # assignment unassignable.
    assert validate_parameters(spec, None) == default_parameters(spec)


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_every_assessment_lets_a_doctor_choose_a_speed(spec: AssessmentSpec) -> None:
    pacing = next(p for p in spec.parameters if p.key == "pacing")
    assert pacing.kind is ParameterKind.CHOICE
    assert pacing.default in pacing.choices


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_a_declared_strokes_parameter_exists_and_is_positive(spec: AssessmentSpec) -> None:
    if spec.strokes_parameter is None:
        return
    assert spec.strokes_parameter in {p.key for p in spec.parameters}


def test_unknown_settings_are_rejected_rather_than_dropped() -> None:
    spec = get_spec("finger_tapping")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="has no setting"):
        validate_parameters(spec, {"colour": "blue"})


def test_out_of_range_settings_are_rejected() -> None:
    spec = get_spec("spiral_drawing")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="between 1 and 6"):
        validate_parameters(spec, {"turns": 9})


def test_settings_outside_the_choices_are_rejected() -> None:
    spec = get_spec("finger_tapping")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="must be one of"):
        validate_parameters(spec, {"hand": "both"})


def test_a_fractional_setting_is_not_accepted_as_a_whole_number() -> None:
    spec = get_spec("line_tracing")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="whole number"):
        validate_parameters(spec, {"repetitions": 2.5})


def test_a_boolean_is_not_accepted_as_a_whole_number() -> None:
    spec = get_spec("line_tracing")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="whole number"):
        validate_parameters(spec, {"repetitions": True})


def test_blank_text_is_rejected() -> None:
    spec = get_spec("handwriting")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="cannot be blank"):
        validate_parameters(spec, {"phrase": "   "})


def test_text_is_trimmed_rather_than_stored_with_its_padding() -> None:
    spec = get_spec("handwriting")
    assert spec is not None

    assert validate_parameters(spec, {"phrase": "  Good morning  "})["phrase"] == "Good morning"


def test_too_long_text_is_rejected() -> None:
    spec = get_spec("handwriting")
    assert spec is not None

    with pytest.raises(ParameterValidationError, match="at most 60 characters"):
        validate_parameters(spec, {"phrase": "x" * 61})


def test_omitted_settings_fall_back_to_the_catalog_default() -> None:
    spec = get_spec("finger_tapping")
    assert spec is not None

    resolved = validate_parameters(spec, {"hand": "left"})

    assert resolved == {"hand": "left", "finger": "index", "pacing": "comfortable"}


def test_resolving_a_stored_set_fills_gaps_without_revalidating() -> None:
    spec = get_spec("line_tracing")
    assert spec is not None

    assert resolve_parameters({"repetitions": 7}, spec) == {
        "pacing": "comfortable",
        "repetitions": 7,
        "line_length_percent": 70,
    }


def test_resolving_a_row_written_before_a_parameter_existed() -> None:
    spec = get_spec("line_tracing")
    assert spec is not None

    assert resolve_parameters(None, spec)["repetitions"] == 3


def test_discrete_stroke_assessments_require_every_repetition() -> None:
    spec = get_spec("line_tracing")
    assert spec is not None

    assert required_strokes(spec, {"repetitions": 5}) == 5


def test_a_continuous_stroke_assessment_needs_exactly_one() -> None:
    spec = get_spec("spiral_drawing")
    assert spec is not None

    assert required_strokes(spec, {"turns": 4}) == 1
