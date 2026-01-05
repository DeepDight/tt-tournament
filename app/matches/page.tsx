export const dynamic = "force-dynamic";
import { Player } from "@/app/interface";
import MatchPage from "@/component/MatchPage";
import { Metadata } from "next";
import createDeps from "@/service/create-deps";
import { CURRENT_TOURNAMENT_ID } from "../const";

const { tournamentService } = createDeps();

export default async function MatchesPage() {
  const tournamentId = CURRENT_TOURNAMENT_ID;
  const players: Player[] = await tournamentService.getPlayers(tournamentId);
  const totalMatchesCount = await tournamentService.getTotalMatchesCount(
    tournamentId
  );

  return <MatchPage players={players} totalMatchesCount={totalMatchesCount} />;
}

export const metadata: Metadata = {
  title: "Матчи летнего турнира 2025 — Теннис. Евроберег",
};
