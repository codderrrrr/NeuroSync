"""Unit tests for the assessment catalog registry."""

import pytest

from neurosync.modules.monitoring.assessment_catalog import (
    ASSESSMENT_CATALOG,
    SUPPORTED_ASSESSMENT_SLUGS,
    AssessmentSpec,
    ExecutionType,
)


def test_catalog_contains_the_expected_assessments() -> None:
    slugs = [spec.slug for spec in ASSESSMENT_CATALOG]
    assert slugs == ["finger_tapping", "spiral_drawing", "line_tracing", "handwriting"]


def test_only_finger_tapping_is_supported() -> None:
    assert frozenset({"finger_tapping"}) == SUPPORTED_ASSESSMENT_SLUGS


def test_every_spec_is_fully_described() -> None:
    for spec in ASSESSMENT_CATALOG:
        assert isinstance(spec, AssessmentSpec)
        assert spec.title
        assert spec.description
        assert spec.instructions
        assert spec.default_duration_seconds > 0


def test_future_assessments_are_canvas_tasks() -> None:
    future = [spec for spec in ASSESSMENT_CATALOG if not spec.is_supported]
    assert future, "the catalog must represent not-yet-implemented assessments"
    for spec in future:
        assert spec.execution_type is ExecutionType.CANVAS_TASK
        assert "not available yet" in spec.instructions.lower()


@pytest.mark.parametrize("spec", ASSESSMENT_CATALOG, ids=lambda spec: spec.slug)
def test_slugs_are_url_safe(spec: AssessmentSpec) -> None:
    assert spec.slug == spec.slug.strip().lower()
    assert spec.slug.replace("_", "").isalnum()
