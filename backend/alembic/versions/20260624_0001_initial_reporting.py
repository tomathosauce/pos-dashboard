"""initial reporting tables

Revision ID: 20260624_0001
Revises:
Create Date: 2026-06-24
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260624_0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "daily_sales_summaries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("source_name", sa.String(length=80), nullable=False),
        sa.Column("business_date", sa.Date(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default="USD"),
        sa.Column("gross_amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("payment_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("receipt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("source_row_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("source_name", "business_date", name="uq_daily_sales_source_date"),
    )
    op.create_index("ix_daily_sales_business_date", "daily_sales_summaries", ["business_date"])

    op.create_table(
        "payment_method_summaries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("source_name", sa.String(length=80), nullable=False),
        sa.Column("business_date", sa.Date(), nullable=False),
        sa.Column("payment_code", sa.String(length=40), nullable=False),
        sa.Column("payment_label", sa.String(length=120), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default="USD"),
        sa.Column("total_amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("payment_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint(
            "source_name",
            "business_date",
            "payment_code",
            name="uq_payment_method_source_date_code",
        ),
    )
    op.create_index("ix_payment_method_business_date", "payment_method_summaries", ["business_date"])

    op.create_table(
        "sync_runs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("source_name", sa.String(length=80), nullable=False),
        sa.Column("business_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("rows_read", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("rows_matched", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("warnings", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("error_text", sa.Text(), nullable=True),
    )
    op.create_index("ix_sync_runs_started_at", "sync_runs", ["started_at"])
    op.create_index("ix_sync_runs_source_date", "sync_runs", ["source_name", "business_date"])


def downgrade() -> None:
    op.drop_index("ix_sync_runs_source_date", table_name="sync_runs")
    op.drop_index("ix_sync_runs_started_at", table_name="sync_runs")
    op.drop_table("sync_runs")
    op.drop_index("ix_payment_method_business_date", table_name="payment_method_summaries")
    op.drop_table("payment_method_summaries")
    op.drop_index("ix_daily_sales_business_date", table_name="daily_sales_summaries")
    op.drop_table("daily_sales_summaries")

