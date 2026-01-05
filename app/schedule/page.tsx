export const dynamic = "force-dynamic";
import { Player } from "@/app/interface";
import Schedule from "@/component/Schedule";

import createDeps from "@/service/create-deps";
import { CURRENT_TOURNAMENT_ID } from "../const";

const { tournamentService } = createDeps();

export default async function MatchesPage() {
  const players: Player[] = await tournamentService.getPlayers(
    CURRENT_TOURNAMENT_ID
  );

  return <Schedule players={players} />;
}
