"""
Supabase implementation of TemplateRepository.

Part of AMA-462: Implement ProgramGenerator Service

This implementation uses the Supabase Python client to interact with
the program_templates table defined in AMA-460.
"""

from typing import Dict, List, Optional

from supabase import Client


class SupabaseTemplateRepository:
    """
    Supabase-backed template repository implementation.

    Queries against the program_templates table which stores reusable
    program structures for the hybrid template-guided LLM approach.
    """

    def __init__(self, client: Client):
        """
        Initialize repository with Supabase client.

        Args:
            client: Authenticated Supabase client
        """
        self._client = client

    def get_by_id(self, template_id: str) -> Optional[Dict]:
        """
        Get a template by its ID.

        Args:
            template_id: The template's UUID as string

        Returns:
            Template dictionary if found, None otherwise
        """
        response = (
            self._client.table("program_templates")
            .select("*")
            .eq("id", template_id)
            .single()
            .execute()
        )
        return response.data if response.data else None

    def get_by_criteria(
        self,
        goal: str,
        experience_level: str,
        sessions_per_week: Optional[int] = None,
        duration_weeks: Optional[int] = None,
    ) -> List[Dict]:
        """
        Find templates matching specified criteria.

        Args:
            goal: Training goal (strength, hypertrophy, etc.)
            experience_level: User experience level
            sessions_per_week: Optional filter for session count
            duration_weeks: Optional filter for duration

        Returns:
            List of matching template dictionaries, ordered by usage_count
        """
        query = (
            self._client.table("program_templates")
            .select("*")
            .eq("goal", goal)
            .eq("experience_level", experience_level)
        )

        if duration_weeks is not None:
            # Allow templates within ±2 weeks of target
            query = query.gte("duration_weeks", max(4, duration_weeks - 2))
            query = query.lte("duration_weeks", min(52, duration_weeks + 2))

        # Order by usage count (most used templates first)
        query = query.order("usage_count", desc=True)

        response = query.execute()
        templates = response.data

        # Filter by sessions_per_week if specified (need to check JSONB structure)
        if sessions_per_week is not None and templates:
            filtered = []
            for template in templates:
                structure = template.get("structure", {})
                weeks = structure.get("weeks", [])
                if weeks:
                    # Check if first week's workout count matches
                    first_week = weeks[0] if weeks else {}
                    workouts = first_week.get("workouts", [])
                    if len(workouts) == sessions_per_week:
                        filtered.append(template)
            return filtered

        return templates

    def get_system_templates(self) -> List[Dict]:
        """
        Get all system-provided templates.

        Returns:
            List of system template dictionaries
        """
        response = (
            self._client.table("program_templates")
            .select("*")
            .eq("is_system_template", True)
            .order("usage_count", desc=True)
            .execute()
        )
        return response.data

    def get_user_templates(self, user_id: str) -> List[Dict]:
        """
        Get all templates created by a specific user.

        Args:
            user_id: The user's ID

        Returns:
            List of user template dictionaries
        """
        response = (
            self._client.table("program_templates")
            .select("*")
            .eq("created_by", user_id)
            .eq("is_system_template", False)
            .order("created_at", desc=True)
            .execute()
        )
        return response.data

    def create(self, data: Dict) -> Dict:
        """
        Create a new template.

        Args:
            data: Template data dictionary

        Returns:
            Created template dictionary with generated ID
        """
        response = (
            self._client.table("program_templates")
            .insert(data)
            .execute()
        )
        return response.data[0]

    def increment_usage_count(self, template_id: str) -> bool:
        """
        Increment the usage count for a template.

        Uses Supabase RPC for atomic increment.

        Args:
            template_id: The template's UUID as string

        Returns:
            True if updated, False if not found
        """
        # First get current count
        response = (
            self._client.table("program_templates")
            .select("usage_count")
            .eq("id", template_id)
            .single()
            .execute()
        )

        if not response.data:
            return False

        current_count = response.data.get("usage_count", 0)

        # Update with incremented count
        update_response = (
            self._client.table("program_templates")
            .update({"usage_count": current_count + 1})
            .eq("id", template_id)
            .execute()
        )

        return len(update_response.data) > 0
