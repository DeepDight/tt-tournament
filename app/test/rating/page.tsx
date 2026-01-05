export const dynamic = "force-dynamic";
import { Match, PrismaClient } from "@prisma/client";
import { Player } from "@/app/interface";
import React from "react";
import { Glicko2 } from "glicko2";

const CALIBRATED_RD = 100;

const prisma = new PrismaClient();

interface PlayerWithRating extends Player {
  rating: number;
  rd: number;
  vol: number;
}

interface RatingChange {
  matchId: number;
  player1: string;
  player2: string;
  result: string;
  player1RatingChange: string;
  player2RatingChange: string;
}

const RatingPage = async () => {
  const players: Player[] = await prisma.user.findMany();
  const matches: Match[] = await prisma.match.findMany({
    orderBy: {
      date: "asc",
    },
  });

  const finalRatings = calculateGlicko2Ratings(players, matches);

  const calibrated = finalRatings.filter((player) => player.rd < CALIBRATED_RD);
  const uncalibrated = finalRatings.filter(
    (player) => player.rd >= CALIBRATED_RD
  );

  return (
    <div className="container pb-32 pt-24">
      <h2 className="heading-l mb-16">Рейтинг по Glicko2</h2>
      <div className="overflow-x-auto mb-8">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th
                scope="col"
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Позиция
              </th>
              <th
                scope="col"
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Имя
              </th>
              <th
                scope="col"
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Фамилия
              </th>
              <th
                scope="col"
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Рейтинг
              </th>
              <th
                scope="col"
                className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Отклонение рейтинга
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {calibrated.map((player: PlayerWithRating, index: number) => (
              <tr key={player.id}>
                <td className="px-6 py-4 whitespace-nowrap">{index + 1}</td>
                <td className="px-6 py-4 whitespace-nowrap">
                  {player.firstName}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  {player.lastName}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  {Math.round(player.rating)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  ±{Math.round(player.rd)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="heading-l mb-16">На калибровке</h2>
      <ul>
        {uncalibrated.map((player) => (
          <li key={player.id}>
            {player.firstName} {player.lastName}
          </li>
        ))}
      </ul>
    </div>
  );
};

function calculateGlicko2Ratings(
  players: Player[],
  matches: Match[]
): PlayerWithRating[] {
  const INITIAL_SETTINGS = {
    tau: 0.5,
    rating: 1500,
    rd: 400,
    vol: 0.06,
  };

  const glicko = new Glicko2(INITIAL_SETTINGS);
  const playerMap = new Map<number, any>(); // Карта для хранения игроков
  const playerDetails = new Map<number, Player>(); // Карта для хранения деталей игроков

  // Инициализация игроков
  players.forEach((player) => {
    const newPlayer = glicko.makePlayer(1500);
    playerMap.set(player.id, newPlayer);
    playerDetails.set(player.id, player);
  });

  matches.forEach((match) => {
    const player1 = playerMap.get(match.player1Id);
    const player2 = playerMap.get(match.player2Id);
    let score1, score2;
    let result;

    if (match.result === "PLAYER1_WIN") {
      score1 = 1.0;
      score2 = 0.0;
      result = `${playerDetails.get(match.player1Id)?.firstName} ${playerDetails.get(match.player1Id)?.lastName
        }`;
    } else if (match.result === "PLAYER2_WIN") {
      score1 = 0.0;
      score2 = 1.0;
      result = `${playerDetails.get(match.player2Id)?.firstName} ${playerDetails.get(match.player2Id)?.lastName
        }`;
    } else {
      score1 = 0.5;
      score2 = 0.5;
      result = "Ничья";
    }

    glicko.addMatch(player1, player2, score1);
  });

  glicko.calculatePlayersRatings(); // Обновляем рейтинги после каждого матча

  // Формируем итоговые рейтинги
  const finalRatings = players.map((player) => {
    const glickoPlayer = playerMap.get(player.id);
    return {
      ...player,
      rating: glickoPlayer.getRating(),
      rd: glickoPlayer.getRd(),
      vol: glickoPlayer.getVol(),
    };
  });

  return finalRatings.sort((a, b) => b.rating - a.rating);
}

export default RatingPage;
